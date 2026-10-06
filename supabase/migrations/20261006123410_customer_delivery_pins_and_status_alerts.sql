-- Optional customer-consented foreground location. Coordinates stay in the
-- same owned address/order rows and are never published to catalogue data.
create or replace function koyas_private.valid_delivery_pin(pin jsonb)
returns boolean language sql immutable set search_path = '' as $$
  select case when pin is null then true
    when jsonb_typeof(pin) <> 'object' then false
    when not (pin ?& array['latitude','longitude','accuracy_meters','captured_at_ms']) then false
    when (pin - array['latitude','longitude','accuracy_meters','captured_at_ms']) <> '{}'::jsonb then false
    when jsonb_typeof(pin->'latitude') <> 'number'
      or jsonb_typeof(pin->'longitude') <> 'number'
      or jsonb_typeof(pin->'accuracy_meters') <> 'number'
      or jsonb_typeof(pin->'captured_at_ms') <> 'number' then false
    else (pin->>'latitude')::numeric between -90 and 90
      and (pin->>'longitude')::numeric between -180 and 180
      and (pin->>'accuracy_meters')::numeric between 0 and 100000
      and (pin->>'captured_at_ms')::numeric between 0 and 4102444800000
    end;
$$;
revoke all on function koyas_private.valid_delivery_pin(jsonb) from public,anon,authenticated;
-- Only guarded RPCs write these tables; their definer evaluates constraints.
alter table public.addresses add column delivery_pin jsonb,
  add constraint addresses_delivery_pin_valid check(koyas_private.valid_delivery_pin(delivery_pin));
alter table public.orders add column delivery_pin jsonb,
  add constraint orders_delivery_pin_valid check(koyas_private.valid_delivery_pin(delivery_pin)),
  add constraint pickup_has_no_delivery_pin check(fulfilment_type='delivery' or delivery_pin is null);
comment on column public.orders.delivery_pin is 'Delivery pin captured from the owned address at checkout; editing or deleting the saved address does not move an existing order.';

create or replace function public.mutate_customer(
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
        insert into public.addresses(user_id, label, recipient_name, phone, line1, city, pincode, instructions, is_default, delivery_pin)
        values(customer, mutation->>'label', mutation->>'recipient_name', mutation->>'phone',
          mutation->>'line1', mutation->>'city', mutation->>'pincode', coalesce(mutation->>'instructions', ''),
          coalesce((mutation->>'is_default')::boolean, false), nullif(mutation->'delivery_pin','null'::jsonb))
        returning to_jsonb(addresses) into result_body;
      else
        update public.addresses set label = mutation->>'label', recipient_name = mutation->>'recipient_name',
          phone = mutation->>'phone', line1 = mutation->>'line1', city = mutation->>'city',
          pincode = mutation->>'pincode', instructions = coalesce(mutation->>'instructions', ''),
          is_default = coalesce((mutation->>'is_default')::boolean, false),
          delivery_pin = case when mutation ? 'delivery_pin' then nullif(mutation->'delivery_pin','null'::jsonb) else delivery_pin end
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

create or replace function public.snapshot_order_contacts()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  profile_name text;
  profile_phone text;
  recipient_name text;
  recipient_phone text;
begin
  select profiles.full_name, profiles.phone
  into profile_name, profile_phone
  from public.profiles as profiles
  where profiles.id = new.user_id;

  new.customer_name_snapshot := pg_catalog.left(
    pg_catalog.btrim(coalesce(profile_name, '')),
    120
  );
  new.customer_phone_snapshot := pg_catalog.left(
    pg_catalog.btrim(coalesce(profile_phone, '')),
    40
  );

  if new.fulfilment_type = 'delivery' then
    select addresses.recipient_name, addresses.phone, addresses.delivery_pin
    into recipient_name, recipient_phone, new.delivery_pin
    from public.addresses as addresses
    where addresses.id = new.address_id
      and addresses.user_id = new.user_id;

    new.delivery_recipient_name_snapshot := pg_catalog.left(
      pg_catalog.btrim(
        coalesce(recipient_name, new.customer_name_snapshot)
      ),
      120
    );
    new.delivery_recipient_phone_snapshot := pg_catalog.left(
      pg_catalog.btrim(
        coalesce(recipient_phone, new.customer_phone_snapshot)
      ),
      40
    );
  else
    new.delivery_pin := null;
    new.delivery_recipient_name_snapshot := null;
    new.delivery_recipient_phone_snapshot := null;
  end if;

  return new;
end;
$$;


revoke all on function public.snapshot_order_contacts() from public,anon,authenticated;

create or replace function public.protect_and_anonymize_deleted_customer()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  -- Share the customer lock used by place_order_v2. A FK alone prevents an
  -- invalid user ID but does not prevent an active order becoming anonymized.
  perform pg_advisory_xact_lock(hashtextextended(old.id::text, 0));
  if exists (select 1 from public.admins where user_id=old.id) then
    raise exception 'Staff accounts must be removed by an authorized administrator';
  end if;
  if exists (select 1 from public.orders where user_id=old.id
    and order_status not in ('collected','delivered','cancelled','rejected')) then
    raise exception 'Complete or cancel active orders before deleting this account';
  end if;
  update public.orders set address_id=null,
    delivery_address_text=case when fulfilment_type='delivery' then 'Removed after account deletion' else null end,
    delivery_instructions='', customer_name_snapshot='Deleted customer',customer_phone_snapshot='',
    delivery_recipient_name_snapshot=null,delivery_recipient_phone_snapshot=null,
    checkout_request=null, delivery_pin=null
  where user_id=old.id;
  return old;
end;
$$;
revoke all on function public.protect_and_anonymize_deleted_customer() from public,anon,authenticated;
notify pgrst, 'reload schema';

-- A status change produces one durable queue item in the order transaction.
-- This queue is reserved for future server push; clients use live order reads.
create or replace function public.queue_status_notification()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.order_status is distinct from new.order_status
    and new.user_id is not null
    and new.order_status in ('ready_for_pickup','out_for_delivery','delivered','collected','cancelled','rejected') then
    insert into public.notification_queue(user_id,order_id,title,body,data)
    values(new.user_id,new.id,'Order #' || new.order_number,
      case new.order_status
        when 'ready_for_pickup' then 'Your order is packed and ready for pickup at Koya Stores.'
        when 'out_for_delivery' then 'Your order is on its way to your delivery address.'
        when 'delivered' then 'Your order has been delivered.'
        when 'collected' then 'Your order has been collected.'
        when 'cancelled' then 'Your order has been cancelled.'
        else 'The store could not fulfil your order.' end,
      jsonb_build_object('order_id',new.id,'status',new.order_status));
  end if;
  return new;
end;
$$;
revoke all on function public.queue_status_notification() from public,anon,authenticated;
notify pgrst, 'reload schema';
