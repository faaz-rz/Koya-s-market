-- Atomic, replay-safe customer and staff configuration requests. This migration
-- preserves catalogue/price data. Release the matching clients with it.
alter table public.store_settings add column revision bigint not null default 0;
alter table public.offers add column revision bigint not null default 0;
alter table public.addresses add column revision bigint not null default 0;
alter table public.profiles add column revision bigint not null default 0;

create function public.bump_row_revision()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.revision := old.revision + 1;
  return new;
end;
$$;
revoke all on function public.bump_row_revision() from public, anon, authenticated;
create trigger settings_revision before update on public.store_settings
for each row execute function public.bump_row_revision();
create trigger offers_revision before update on public.offers
for each row execute function public.bump_row_revision();
create trigger addresses_revision before update on public.addresses
for each row execute function public.bump_row_revision();
create trigger profiles_revision before update on public.profiles
for each row execute function public.bump_row_revision();

-- Repair only ambiguous default flags in pre-existing address books, retaining
-- the most recently changed default. No address or order is removed.
with ranked as (
  select id, row_number() over (
    partition by user_id order by updated_at desc, id
  ) as position from public.addresses where is_default
)
update public.addresses set is_default = false
where id in (select id from ranked where position > 1);
create unique index addresses_one_default_per_customer
on public.addresses(user_id) where is_default;

create table public.configuration_requests (
  user_id uuid not null references auth.users(id) on delete cascade,
  request_id uuid not null,
  request jsonb not null,
  result jsonb not null,
  created_at timestamptz not null default now(),
  primary key(user_id, request_id)
);
alter table public.configuration_requests enable row level security;
revoke all on public.configuration_requests from public, anon, authenticated;

create function public.admin_mutate_configuration(
  request_id uuid, expected_revision bigint, mutation jsonb
) returns jsonb
language plpgsql security definer set search_path = '' set lock_timeout = '5s'
as $$
declare
  operation text := mutation->>'action';
  target uuid := (mutation->>'target_offer_id')::uuid;
  receipt public.configuration_requests%rowtype;
  request_body jsonb := jsonb_build_object('expected_revision', expected_revision, 'mutation', mutation);
  current_revision bigint;
  result_body jsonb;
begin
  if not public.is_admin() then raise exception 'Admin access required'; end if;
  if request_id is null or mutation is null or jsonb_typeof(mutation) <> 'object'
    or operation is null or operation not in ('pricing', 'offer')
    or octet_length(mutation::text) > 8192 then
    raise exception 'Invalid configuration request';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('configuration:' || auth.uid()::text || ':' || request_id::text, 0));
  select * into receipt from public.configuration_requests r
  where r.user_id = auth.uid() and r.request_id = admin_mutate_configuration.request_id;
  if receipt.request_id is not null then
    if receipt.request is distinct from request_body then
      raise sqlstate 'PT409' using message = 'Request ID was already used with different details.';
    end if;
    return receipt.result;
  end if;
  if operation = 'pricing' then
    select revision into current_revision from public.store_settings where id = 1 for update;
    if not found then raise exception 'Store settings not found'; end if;
    if expected_revision is distinct from current_revision then
      raise sqlstate 'PT409' using message = 'Order pricing changed while you were editing. Refresh and try again.';
    end if;
    perform public.admin_update_order_pricing(
      (mutation->>'requested_minimum_order_paise')::integer,
      (mutation->>'requested_delivery_charge_paise')::integer,
      (mutation->>'requested_free_delivery_threshold_paise')::integer
    );
    select to_jsonb(s) into result_body from public.store_settings s where id = 1;
  else
    if target is not null then
      select revision into current_revision from public.offers where id = target for update;
      if not found then raise exception 'Offer not found'; end if;
      if expected_revision is distinct from current_revision then
        raise sqlstate 'PT409' using message = 'This offer changed while you were editing. Refresh and try again.';
      end if;
    end if;
    target := public.admin_save_offer(
      target, mutation->>'requested_code', mutation->>'requested_title', mutation->>'requested_description',
      (mutation->>'requested_minimum_subtotal_paise')::integer,
      mutation->>'requested_discount_type', (mutation->>'requested_discount_value')::integer,
      (mutation->>'requested_maximum_discount_paise')::integer,
      (mutation->>'requested_free_product_id')::uuid, (mutation->>'requested_free_quantity')::integer,
      (mutation->>'requested_fulfilment')::public.fulfilment_type,
      (mutation->>'requested_starts_at')::timestamptz, (mutation->>'requested_ends_at')::timestamptz,
      (mutation->>'requested_total_redemption_limit')::integer,
      (mutation->>'requested_per_customer_limit')::integer, (mutation->>'requested_active')::boolean
    );
    select to_jsonb(o) into result_body from public.offers o where id = target;
  end if;
  insert into public.configuration_requests(user_id, request_id, request, result)
  values(auth.uid(), request_id, request_body, result_body);
  return result_body;
end;
$$;
revoke all on function public.admin_mutate_configuration(uuid, bigint, jsonb) from public, anon, authenticated;
grant execute on function public.admin_mutate_configuration(uuid, bigint, jsonb) to authenticated;
revoke all on function public.admin_update_order_pricing(integer, integer, integer) from public, anon, authenticated;
revoke all on function public.admin_save_offer(
  uuid, text, text, text, integer, text, integer, integer, uuid, integer,
  public.fulfilment_type, timestamptz, timestamptz, integer, integer, boolean
) from public, anon, authenticated;

create function public.mutate_customer(
  request_id uuid, expected_revision bigint, mutation jsonb
) returns jsonb
language plpgsql security definer set search_path = '' set lock_timeout = '5s'
as $$
declare
  customer uuid := auth.uid();
  operation text := mutation->>'action';
  target uuid := (mutation->>'address_id')::uuid;
  previous public.addresses%rowtype;
  receipt public.configuration_requests%rowtype;
  request_body jsonb := jsonb_build_object('expected_revision', expected_revision, 'mutation', mutation);
  result_body jsonb;
  current_revision bigint;
begin
  if customer is null then raise exception 'Authentication required'; end if;
  if request_id is null or mutation is null or jsonb_typeof(mutation) <> 'object'
    or operation is null or operation not in ('save_address', 'delete_address', 'default_address', 'save_profile')
    or octet_length(mutation::text) > 8192 then
    raise exception 'Invalid customer request';
  end if;
  -- Same lock as checkout/deletion: no half-changed address/contact snapshot,
  -- and simultaneous requests cannot create two defaults or duplicate saves.
  perform pg_advisory_xact_lock(hashtextextended(customer::text, 0));
  select * into receipt from public.configuration_requests r
  where r.user_id = customer and r.request_id = mutate_customer.request_id;
  if receipt.request_id is not null then
    if receipt.request is distinct from request_body then
      raise sqlstate 'PT409' using message = 'Request ID was already used with different details.';
    end if;
    return receipt.result;
  end if;
  if operation = 'save_profile' then
    select revision into current_revision from public.profiles where id = customer for update;
    if not found then raise exception 'Profile not found'; end if;
    if expected_revision is distinct from current_revision then
      raise sqlstate 'PT409' using message = 'Your profile changed while you were editing. Refresh and try again.';
    end if;
    if length(btrim(coalesce(mutation->>'full_name', ''))) not between 2 and 120 then
      raise exception 'Enter a name between 2 and 120 characters';
    end if;
    update public.profiles set full_name = btrim(mutation->>'full_name'), phone = mutation->>'phone'
    where id = customer returning to_jsonb(profiles) into result_body;
  else
    if target is not null then
      select * into previous from public.addresses where id = target and user_id = customer for update;
      if previous.id is null then raise exception 'Address not found'; end if;
      if expected_revision is distinct from previous.revision then
        raise sqlstate 'PT409' using message = 'This address changed while you were editing. Refresh and try again.';
      end if;
    elsif operation <> 'save_address' then
      raise exception 'Address not found';
    end if;
    if operation = 'delete_address' then
      delete from public.addresses where id = target and user_id = customer;
      result_body := jsonb_build_object('id', target, 'deleted', true);
    elsif operation = 'default_address' then
      update public.addresses set is_default = false where user_id = customer and is_default and id <> target;
      update public.addresses set is_default = true where id = target and user_id = customer and not is_default;
      select to_jsonb(a) into result_body from public.addresses a where id = target;
    else
      if target is null and (select count(*) from public.addresses where user_id = customer) >= 20 then
        raise exception 'You can save up to 20 addresses';
      end if;
      if coalesce((mutation->>'is_default')::boolean, false) then
        update public.addresses set is_default = false
        where user_id = customer and is_default and id is distinct from target;
      end if;
      if target is null then
        insert into public.addresses(user_id, label, recipient_name, phone, line1, city, pincode, instructions, is_default)
        values(customer, mutation->>'label', mutation->>'recipient_name', mutation->>'phone',
          mutation->>'line1', mutation->>'city', mutation->>'pincode', coalesce(mutation->>'instructions', ''),
          coalesce((mutation->>'is_default')::boolean, false))
        returning to_jsonb(addresses) into result_body;
      else
        update public.addresses set label = mutation->>'label', recipient_name = mutation->>'recipient_name',
          phone = mutation->>'phone', line1 = mutation->>'line1', city = mutation->>'city',
          pincode = mutation->>'pincode', instructions = coalesce(mutation->>'instructions', ''),
          is_default = coalesce((mutation->>'is_default')::boolean, false)
        where id = target and user_id = customer returning to_jsonb(addresses) into result_body;
      end if;
    end if;
  end if;
  insert into public.configuration_requests(user_id, request_id, request, result)
  values(customer, request_id, request_body, result_body);
  return result_body;
end;
$$;
revoke all on function public.mutate_customer(uuid, bigint, jsonb) from public, anon, authenticated;
grant execute on function public.mutate_customer(uuid, bigint, jsonb) to authenticated;
-- All browser/mobile writes must pass revision, ownership and receipt checks.
revoke insert, update, delete on public.addresses from public, anon, authenticated;
revoke update on public.profiles from public, anon, authenticated;

-- Return the profile revision through the existing conditional snapshot. The
-- other revised rows already use to_jsonb(), so their revisions flow through.
-- Keep the snapshot function intact except for its profile projection.
do $$
declare definition text;
begin
  select pg_get_functiondef('public.sync_store(jsonb,jsonb,text)'::regprocedure) into definition;
  if position('''full_name'',p.full_name,''phone'',p.phone' in definition) = 0 then
    raise exception 'Unexpected sync_store profile projection; update this migration before applying';
  end if;
  definition := replace(definition,
    '''full_name'',p.full_name,''phone'',p.phone',
    '''full_name'',p.full_name,''phone'',p.phone,''revision'',p.revision');
  execute definition;
end;
$$;
alter function public.admin_mark_order_paid(uuid) set lock_timeout = '5s';
notify pgrst, 'reload schema';
