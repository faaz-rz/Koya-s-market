-- Concurrent checkout and staff inventory writes. No prices/stock are reset.
-- Lock order: customer -> offer -> slot -> products (UUID order). Existing-order
-- operations lock the order first, then its products in the same UUID order.
alter table public.orders add column checkout_request jsonb;
alter table public.products add column revision bigint not null default 0;

create function public.bump_product_revision()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.revision := old.revision + 1;
  return new;
end;
$$;
create trigger products_revision before update on public.products
for each row execute function public.bump_product_revision();

create function public.lock_inventory_products(product_ids uuid[])
returns void language plpgsql set search_path = '' as $$
begin
  perform id from public.products
  where id = any(product_ids) order by id for update;
end;
$$;
revoke all on function public.lock_inventory_products(uuid[])
from public, anon, authenticated;

alter function public.place_order_v2(
  jsonb, public.fulfilment_type, uuid, date, uuid,
  public.payment_method, text, text, text
) rename to place_order_priced_internal;
revoke all on function public.place_order_priced_internal(
  jsonb, public.fulfilment_type, uuid, date, uuid,
  public.payment_method, text, text, text
) from public, anon, authenticated;

create function public.place_order_v2(
  requested_items jsonb,
  requested_fulfilment public.fulfilment_type,
  requested_address_id uuid,
  requested_date date,
  requested_slot_id uuid,
  requested_payment public.payment_method,
  requested_instructions text,
  requested_idempotency_key text,
  requested_offer_code text
) returns uuid
language plpgsql security definer set search_path = '' set lock_timeout = '5s'
as $$
declare
  customer_id uuid := auth.uid();
  canonical_items jsonb;
  canonical_request jsonb;
  previous public.orders%rowtype;
  product_ids uuid[];
  free_product_id uuid;
  order_id uuid;
  offer_code text := nullif(upper(btrim(coalesce(requested_offer_code, ''))), '');
begin
  if customer_id is null then raise exception 'Authentication required'; end if;
  if requested_items is null or jsonb_typeof(requested_items) <> 'array' then
    raise exception 'Invalid cart';
  end if;
  if jsonb_array_length(requested_items) not between 1 and 50
    or octet_length(requested_items::text) > 32768 then
    raise exception 'Cart must contain between 1 and 50 items';
  end if;
  if requested_fulfilment is null or requested_payment is null
    or requested_date is null or requested_slot_id is null then
    raise exception 'Select valid fulfilment and payment details';
  end if;
  if length(coalesce(requested_idempotency_key, '')) not between 8 and 128
    or requested_idempotency_key !~ '^[A-Za-z0-9._:-]+$' then
    raise exception 'Invalid idempotency key';
  end if;
  if length(coalesce(requested_instructions, '')) > 500 then
    raise exception 'Delivery instructions are too long';
  end if;
  if exists (
    select 1 from jsonb_to_recordset(requested_items) as x(product_id uuid, quantity integer)
    where product_id is null or quantity is null or quantity not between 1 and 99
  ) then raise exception 'Invalid quantity or product'; end if;
  if exists (
    select 1 from jsonb_to_recordset(requested_items) as x(product_id uuid, quantity integer)
    group by product_id having sum(quantity) > 99
  ) then raise exception 'Invalid quantity'; end if;

  select jsonb_agg(jsonb_build_object('product_id', product_id, 'quantity', quantity) order by product_id),
         array_agg(product_id order by product_id)
  into canonical_items, product_ids
  from (
    select product_id, sum(quantity)::integer as quantity
    from jsonb_to_recordset(requested_items) as x(product_id uuid, quantity integer)
    group by product_id
  ) as lines;
  canonical_request := jsonb_build_object(
    'items', canonical_items, 'fulfilment', requested_fulfilment,
    'address_id', case when requested_fulfilment = 'delivery' then requested_address_id end,
    'date', requested_date, 'slot_id', requested_slot_id,
    'payment', requested_payment, 'instructions', coalesce(requested_instructions, ''),
    'offer_code', offer_code
  );
  perform pg_advisory_xact_lock(hashtextextended(customer_id::text, 0));
  select * into previous from public.orders
  where user_id = customer_id and idempotency_key = requested_idempotency_key;
  if previous.id is not null then
    if previous.checkout_request is distinct from canonical_request then
      raise sqlstate 'PT409' using message =
        'Checkout already exists with different details. Check your orders before starting again.';
    end if;
    return previous.id;
  end if;

  -- Offers must be locked BEFORE basket products. Free gifts are included in
  -- the sorted lock set, even if the same SKU is also being bought normally.
  if offer_code is not null then
    select offers.free_product_id into free_product_id from public.offers
    where code = offer_code for update;
    if not found then raise exception 'Offer code was not found'; end if;
  end if;
  perform id from public.fulfilment_slots where id = requested_slot_id for update;
  perform public.lock_inventory_products(array_append(product_ids, free_product_id));
  order_id := public.place_order_priced_internal(
    canonical_items, requested_fulfilment, requested_address_id, requested_date,
    requested_slot_id, requested_payment, requested_instructions,
    requested_idempotency_key, offer_code
  );
  update public.orders set checkout_request = canonical_request where id = order_id;
  return order_id;
end;
$$;
revoke all on function public.place_order_v2(
  jsonb, public.fulfilment_type, uuid, date, uuid, public.payment_method, text, text, text
) from public, anon, authenticated;
grant execute on function public.place_order_v2(
  jsonb, public.fulfilment_type, uuid, date, uuid, public.payment_method, text, text, text
) to authenticated;

-- Preserve existing transition/audit rules, adding ordered inventory locks and
-- making identical cancellation/status retries harmless.
alter function public.cancel_own_order(uuid, text) rename to cancel_own_order_internal;
revoke all on function public.cancel_own_order_internal(uuid, text) from public, anon, authenticated;
create function public.cancel_own_order(target_order_id uuid, reason text default null)
returns void language plpgsql security definer set search_path = '' set lock_timeout = '5s' as $$
declare previous public.orders%rowtype;
begin
  select * into previous from public.orders
  where id = target_order_id and user_id = auth.uid() for update;
  if previous.id is null then raise exception 'Order not found'; end if;
  if previous.order_status = 'cancelled' then return; end if;
  perform public.lock_inventory_products(array(
    select product_id from public.order_items where order_id = target_order_id
  ));
  perform public.cancel_own_order_internal(target_order_id, reason);
end;
$$;
revoke all on function public.cancel_own_order(uuid, text) from public, anon, authenticated;
grant execute on function public.cancel_own_order(uuid, text) to authenticated;

alter function public.update_order_status(uuid, public.order_status, timestamptz, text, text)
rename to update_order_status_internal;
revoke all on function public.update_order_status_internal(uuid, public.order_status, timestamptz, text, text)
from public, anon, authenticated;
create function public.update_order_status(
  target_order_id uuid, next_status public.order_status,
  ready_at timestamptz default null, delivery_name text default null, delivery_phone text default null
) returns void language plpgsql security definer set search_path = '' set lock_timeout = '5s' as $$
declare previous public.orders%rowtype;
begin
  if not public.is_admin() then raise exception 'Admin access required'; end if;
  select * into previous from public.orders where id = target_order_id for update;
  if previous.id is null then raise exception 'Order not found'; end if;
  if previous.order_status = next_status then return; end if;
  if next_status in ('cancelled', 'rejected') then
    perform public.lock_inventory_products(array(
      select product_id from public.order_items where order_id = target_order_id
    ));
  end if;
  perform public.update_order_status_internal(target_order_id, next_status, ready_at, delivery_name, delivery_phone);
end;
$$;
revoke all on function public.update_order_status(uuid, public.order_status, timestamptz, text, text)
from public, anon, authenticated;
grant execute on function public.update_order_status(uuid, public.order_status, timestamptz, text, text)
to authenticated;

create or replace function public.expire_abandoned_online_orders(requested_limit integer default 100)
returns integer language plpgsql security definer set search_path = '' set lock_timeout = '5s' as $$
declare expired_ids uuid[];
begin
  -- Claim the WHOLE batch before touching inventory; SKIP LOCKED also permits
  -- multiple expiry workers without double-restoring stock.
  select array_agg(id) into expired_ids from (
    select id from public.orders
    where payment_method = 'online' and payment_status in ('pending', 'failed')
      and order_status = 'placed' and payment_expires_at <= now()
    order by payment_expires_at, id
    limit greatest(1, least(coalesce(requested_limit, 100), 500))
    for update skip locked
  ) as claimed;
  if expired_ids is null then return 0; end if;
  perform public.lock_inventory_products(array(
    select product_id from public.order_items where order_id = any(expired_ids)
  ));
  update public.orders set order_status = 'cancelled', payment_status = 'cancelled',
    cancellation_reason = 'Online payment window expired'
  where id = any(expired_ids);
  update public.products as product
  set stock_quantity = product.stock_quantity + restored.quantity
  from (
    select product_id, sum(quantity)::integer as quantity from public.order_items
    where order_id = any(expired_ids) and product_id is not null group by product_id
  ) as restored where product.id = restored.product_id;
  return cardinality(expired_ids);
end;
$$;
revoke all on function public.expire_abandoned_online_orders(integer) from public, anon, authenticated;
grant execute on function public.expire_abandoned_online_orders(integer) to service_role;

-- An inventory operation and its receipt commit together. An HTTP timeout may
-- be retried with the SAME request_id without creating another product or
-- applying a stock delta twice. Keep receipts while clients may retry them.
create table public.admin_inventory_requests (
  admin_id uuid not null references auth.users(id) on delete cascade,
  request_id uuid not null,
  request jsonb not null,
  result jsonb not null,
  created_at timestamptz not null default now(),
  primary key (admin_id, request_id)
);
alter table public.admin_inventory_requests enable row level security;
revoke all on public.admin_inventory_requests from public, anon, authenticated;

create function public.admin_mutate_product(
  request_id uuid, expected_revision bigint, mutation jsonb
) returns jsonb
language plpgsql security definer set search_path = '' set lock_timeout = '5s'
as $$
declare
  operation text := mutation->>'action';
  product_id uuid := (mutation->>'target_product_id')::uuid;
  previous public.products%rowtype;
  receipt public.admin_inventory_requests%rowtype;
  request_body jsonb := jsonb_build_object('expected_revision', expected_revision, 'mutation', mutation);
  result_body jsonb;
begin
  if not public.is_admin() then raise exception 'Admin access required'; end if;
  if request_id is null or mutation is null or jsonb_typeof(mutation) <> 'object'
    or operation is null or operation not in ('save', 'set_stock', 'adjust_stock')
    or octet_length(mutation::text) > 32768 then
    raise exception 'Invalid inventory request';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('inventory:' || auth.uid()::text || ':' || request_id::text, 0));
  select * into receipt from public.admin_inventory_requests as requests
  where requests.admin_id = auth.uid() and requests.request_id = admin_mutate_product.request_id;
  if receipt.request_id is not null then
    if receipt.request is distinct from request_body then
      raise sqlstate 'PT409' using message = 'Inventory request was already used with different details.';
    end if;
    return receipt.result;
  end if;
  if product_id is not null then
    select * into previous from public.products where id = product_id for update;
    if previous.id is null then raise exception 'Product not found'; end if;
    if operation <> 'adjust_stock' and expected_revision is distinct from previous.revision then
      raise sqlstate 'PT409' using message =
        'This product changed while you were editing it. Refresh inventory and try again.';
    end if;
  elsif operation <> 'save' then
    raise exception 'Product not found';
  end if;

  if operation = 'save' then
    product_id := public.admin_save_product_v2(
      product_id, (mutation->>'product_category_id')::uuid,
      mutation->>'product_name', mutation->>'product_description', mutation->>'product_unit',
      (mutation->>'product_price_paise')::integer,
      (mutation->>'product_discount_price_paise')::integer,
      (mutation->>'product_stock_quantity')::integer,
      (mutation->>'product_featured')::boolean, (mutation->>'product_active')::boolean,
      (mutation->>'product_available')::boolean, mutation->>'product_subcategory',
      mutation->>'product_brand', mutation->>'product_billing_name', mutation->>'product_print_name',
      mutation->>'product_item_code', mutation->>'product_barcode', mutation->>'product_image_path',
      (mutation->>'remove_product_image')::boolean
    );
  elsif operation = 'set_stock' then
    if mutation->>'requested_stock' is null then raise exception 'Stock is required'; end if;
    perform public.admin_set_product_stock(product_id, (mutation->>'requested_stock')::integer);
  else
    if mutation->>'stock_delta' is null then raise exception 'Stock adjustment is required'; end if;
    perform public.admin_adjust_product_stock(product_id, (mutation->>'stock_delta')::integer);
  end if;
  select jsonb_build_object('product_id', id, 'stock_quantity', stock_quantity, 'revision', revision)
  into result_body from public.products where id = product_id;
  insert into public.admin_inventory_requests(admin_id, request_id, request, result)
  values (auth.uid(), request_id, request_body, result_body);
  return result_body;
end;
$$;
revoke all on function public.admin_mutate_product(uuid, bigint, jsonb) from public, anon, authenticated;
grant execute on function public.admin_mutate_product(uuid, bigint, jsonb) to authenticated;

-- Do not leave the old, unversioned write APIs available as a bypass.
revoke all on function public.admin_set_product_stock(uuid, integer) from public, anon, authenticated;
revoke all on function public.admin_adjust_product_stock(uuid, integer) from public, anon, authenticated;
revoke all on function public.admin_save_product_v2(
  uuid, uuid, text, text, text, integer, integer, integer,
  boolean, boolean, boolean, text, text, text, text, text, text, text, boolean
) from public, anon, authenticated;
revoke all on function public.admin_save_product(
  uuid, uuid, text, text, text, integer, integer, integer, boolean, text, text, text
) from public, anon, authenticated;

notify pgrst, 'reload schema';
