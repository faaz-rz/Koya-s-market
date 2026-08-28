-- Customer-app security controls. These rules live in PostgreSQL so they also
-- apply to modified clients and direct API calls.

-- Keep the original, server-authoritative pricing/stock transaction private
-- and expose a validation/rate-limit wrapper with the original API signature.
alter function public.place_order(
  jsonb, public.fulfilment_type, uuid, date, uuid,
  public.payment_method, text, text
) rename to place_order_internal;

revoke all on function public.place_order_internal(
  jsonb, public.fulfilment_type, uuid, date, uuid,
  public.payment_method, text, text
) from public, anon, authenticated;

create function public.place_order(
  requested_items jsonb,
  requested_fulfilment public.fulfilment_type,
  requested_address_id uuid,
  requested_date date,
  requested_slot_id uuid,
  requested_payment public.payment_method,
  requested_instructions text,
  requested_idempotency_key text
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  existing_order_id uuid;
  active_order_count integer;
  recent_order_count integer;
begin
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;
  if requested_items is null or pg_catalog.jsonb_typeof(requested_items) <> 'array' then
    raise exception 'Invalid cart';
  end if;
  if pg_catalog.jsonb_array_length(requested_items) < 1
    or pg_catalog.jsonb_array_length(requested_items) > 50
    or pg_catalog.octet_length(requested_items::text) > 32768 then
    raise exception 'Cart must contain between 1 and 50 items';
  end if;
  if pg_catalog.length(coalesce(requested_instructions, '')) > 500 then
    raise exception 'Delivery instructions are too long';
  end if;
  if pg_catalog.length(coalesce(requested_idempotency_key, '')) not between 8 and 128
    or requested_idempotency_key !~ '^[A-Za-z0-9._:-]+$' then
    raise exception 'Invalid idempotency key';
  end if;

  -- Serialize placement for one customer. Without this lock, parallel calls
  -- could all observe the same pre-limit count and then pass together.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(current_user_id::text, 0)
  );

  select orders.id into existing_order_id
  from public.orders
  where orders.user_id = current_user_id
    and orders.idempotency_key = requested_idempotency_key;
  if existing_order_id is not null then
    return existing_order_id;
  end if;

  select pg_catalog.count(*) into active_order_count
  from public.orders
  where user_id = current_user_id
    and order_status not in ('collected', 'delivered', 'cancelled', 'rejected');
  if active_order_count >= 3 then
    raise exception 'Too many active orders';
  end if;

  select pg_catalog.count(*) into recent_order_count
  from public.orders
  where user_id = current_user_id
    and created_at >= pg_catalog.now() - interval '1 hour';
  if recent_order_count >= 10 then
    raise exception 'Order limit reached. Please try again later';
  end if;

  return public.place_order_internal(
    requested_items,
    requested_fulfilment,
    requested_address_id,
    requested_date,
    requested_slot_id,
    requested_payment,
    requested_instructions,
    requested_idempotency_key
  );
end;
$$;

revoke all on function public.place_order(
  jsonb, public.fulfilment_type, uuid, date, uuid,
  public.payment_method, text, text
) from public, anon;
grant execute on function public.place_order(
  jsonb, public.fulfilment_type, uuid, date, uuid,
  public.payment_method, text, text
) to authenticated;

create index if not exists orders_user_active_security_idx
  on public.orders(user_id, created_at desc)
  where order_status not in ('collected', 'delivered', 'cancelled', 'rejected');

-- Unpaid online orders reserve stock for a bounded period rather than forever.
alter table public.orders
  add column if not exists payment_expires_at timestamptz;

create function public.set_online_payment_expiry()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.payment_method = 'online'
    and new.payment_status in ('pending', 'failed')
    and new.payment_expires_at is null then
    new.payment_expires_at := pg_catalog.now() + interval '20 minutes';
  end if;
  return new;
end;
$$;

create trigger set_online_payment_expiry
before insert on public.orders
for each row execute function public.set_online_payment_expiry();

update public.orders
set payment_expires_at = created_at + interval '20 minutes'
where payment_method = 'online'
  and payment_status in ('pending', 'failed')
  and payment_expires_at is null;

alter table public.orders
  add constraint orders_online_payment_expiry_required
  check (
    payment_method <> 'online'
    or payment_status in ('paid', 'refunded', 'cancelled')
    or payment_expires_at is not null
  ) not valid;

create index if not exists orders_expired_online_payment_idx
  on public.orders(payment_expires_at)
  where payment_method = 'online'
    and payment_status in ('pending', 'failed')
    and order_status = 'placed';

create function public.expire_abandoned_online_orders(
  requested_limit integer default 100
) returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  expired_order record;
  expired_count integer := 0;
  bounded_limit integer := greatest(
    1,
    least(coalesce(requested_limit, 100), 500)
  );
begin
  for expired_order in
    select orders.id
    from public.orders
    where payment_method = 'online'
      and payment_status in ('pending', 'failed')
      and order_status = 'placed'
      and payment_expires_at <= pg_catalog.now()
    order by payment_expires_at
    for update skip locked
    limit bounded_limit
  loop
    update public.orders
    set order_status = 'cancelled',
        payment_status = 'cancelled',
        cancellation_reason = 'Online payment window expired'
    where id = expired_order.id;

    update public.products as product
    set stock_quantity = product.stock_quantity + restored.quantity
    from (
      select product_id, pg_catalog.sum(quantity)::integer as quantity
      from public.order_items
      where order_id = expired_order.id and product_id is not null
      group by product_id
    ) as restored
    where product.id = restored.product_id;

    expired_count := expired_count + 1;
  end loop;
  return expired_count;
end;
$$;

revoke all on function public.expire_abandoned_online_orders(integer)
  from public, anon, authenticated;
grant execute on function public.expire_abandoned_online_orders(integer)
  to service_role;

-- Device registration is RPC-only. A token can be atomically transferred when
-- the same device signs into a different account, and one user is capped at
-- five recent devices.
drop policy if exists device_tokens_own_all on public.device_tokens;

create function public.register_device_token(
  requested_token text,
  requested_platform text
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
begin
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;
  if requested_platform not in ('android', 'ios', 'web') then
    raise exception 'Invalid device platform';
  end if;
  if pg_catalog.length(coalesce(requested_token, '')) not between 20 and 4096
    or requested_token ~ '[[:space:]]' then
    raise exception 'Invalid device token';
  end if;

  insert into public.device_tokens(user_id, token, platform, updated_at)
  values (current_user_id, requested_token, requested_platform, pg_catalog.now())
  on conflict (token) do update
  set user_id = excluded.user_id,
      platform = excluded.platform,
      updated_at = excluded.updated_at;

  delete from public.device_tokens
  where user_id = current_user_id
    and id not in (
      select id
      from public.device_tokens
      where user_id = current_user_id
      order by updated_at desc, id
      limit 5
    );
end;
$$;

create function public.unregister_device_token(
  requested_token text
) returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.device_tokens
  where user_id = auth.uid() and token = requested_token;
$$;

revoke all on function public.register_device_token(text, text)
  from public, anon;
revoke all on function public.unregister_device_token(text)
  from public, anon;
grant execute on function public.register_device_token(text, text)
  to authenticated;
grant execute on function public.unregister_device_token(text)
  to authenticated;

create index if not exists device_tokens_user_recency_idx
  on public.device_tokens(user_id, updated_at desc);

-- Bound customer-controlled strings at the data boundary. NOT VALID preserves
-- older imported rows while still enforcing the checks for new/changed rows.
alter table public.profiles
  add constraint profiles_full_name_length
  check (pg_catalog.length(full_name) <= 120) not valid,
  add constraint profiles_phone_format
  check (
    phone is null or phone = ''
    or phone ~ '^[0-9+() -]{7,32}$'
  ) not valid;

alter table public.addresses
  add constraint addresses_label_length
  check (pg_catalog.length(pg_catalog.btrim(label)) between 1 and 40) not valid,
  add constraint addresses_recipient_name_length
  check (pg_catalog.length(pg_catalog.btrim(recipient_name)) between 2 and 120) not valid,
  add constraint addresses_phone_format
  check (phone ~ '^[0-9+() -]{7,32}$') not valid,
  add constraint addresses_line1_length
  check (pg_catalog.length(pg_catalog.btrim(line1)) between 3 and 300) not valid,
  add constraint addresses_city_length
  check (pg_catalog.length(pg_catalog.btrim(city)) between 2 and 120) not valid,
  add constraint addresses_instructions_length
  check (pg_catalog.length(instructions) <= 500) not valid;
