-- Make every order self-contained for fulfilment and record when revenue is
-- actually received. These snapshots must not change when a customer later
-- edits their profile or saved address.
alter table public.orders
  add column if not exists customer_name_snapshot text not null default '',
  add column if not exists customer_phone_snapshot text not null default '',
  add column if not exists delivery_recipient_name_snapshot text,
  add column if not exists delivery_recipient_phone_snapshot text,
  add column if not exists paid_at timestamptz;

-- Do this before the contact backfill, because the table's updated_at trigger
-- will stamp those later updates with the migration time. Online payment
-- events are the best historical source; updated_at is the legacy fallback.
update public.orders as orders
set paid_at = coalesce(
  (
    select pg_catalog.min(events.created_at)
    from public.payment_events as events
    where events.order_id = orders.id
      and events.event_type in ('payment_verified', 'payment.captured')
  ),
  orders.updated_at,
  orders.created_at
)
where orders.payment_status = 'paid'
  and orders.paid_at is null;

update public.orders as orders
set customer_name_snapshot = pg_catalog.left(
      pg_catalog.btrim(coalesce(profiles.full_name, '')),
      120
    ),
    customer_phone_snapshot = pg_catalog.left(
      pg_catalog.btrim(coalesce(profiles.phone, '')),
      40
    )
from public.profiles as profiles
where profiles.id = orders.user_id;

update public.orders as orders
set delivery_recipient_name_snapshot = pg_catalog.left(
      pg_catalog.btrim(addresses.recipient_name),
      120
    ),
    delivery_recipient_phone_snapshot = pg_catalog.left(
      pg_catalog.btrim(addresses.phone),
      40
    )
from public.addresses as addresses
where orders.fulfilment_type = 'delivery'
  and addresses.id = orders.address_id
  and addresses.user_id = orders.user_id;

-- A saved address may have been deleted since an old order was placed. The
-- customer snapshot is the safest available fallback for those legacy rows.
update public.orders
set delivery_recipient_name_snapshot = coalesce(
      delivery_recipient_name_snapshot,
      customer_name_snapshot
    ),
    delivery_recipient_phone_snapshot = coalesce(
      delivery_recipient_phone_snapshot,
      customer_phone_snapshot
    )
where fulfilment_type = 'delivery';

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
    select addresses.recipient_name, addresses.phone
    into recipient_name, recipient_phone
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
    new.delivery_recipient_name_snapshot := null;
    new.delivery_recipient_phone_snapshot := null;
  end if;

  return new;
end;
$$;

drop trigger if exists snapshot_order_contacts on public.orders;
create trigger snapshot_order_contacts
before insert on public.orders
for each row execute function public.snapshot_order_contacts();

-- paid_at is also populated for service-role Razorpay updates, keeping manual
-- and online payment reporting on the same accounting timeline.
create or replace function public.set_order_paid_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.payment_status = 'paid'
    and new.paid_at is null then
    new.paid_at := pg_catalog.now();
  end if;
  return new;
end;
$$;

drop trigger if exists set_order_paid_at on public.orders;
create trigger set_order_paid_at
before insert or update of payment_status on public.orders
for each row execute function public.set_order_paid_at();

-- A cash order cannot be completed first and forgotten in the pending-payment
-- state. Staff must explicitly record the handoff before the final transition.
create or replace function public.require_payment_before_order_completion()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.order_status is distinct from old.order_status
    and (
      (
        new.payment_method = 'pay_at_store'
        and new.order_status = 'collected'
      )
      or (
        new.payment_method = 'cash_on_delivery'
        and new.order_status = 'delivered'
      )
    )
    and new.payment_status <> 'paid' then
    raise exception 'Record payment before completing this order';
  end if;
  return new;
end;
$$;

drop trigger if exists require_payment_before_order_completion
on public.orders;
create trigger require_payment_before_order_completion
before update of order_status on public.orders
for each row execute function public.require_payment_before_order_completion();

alter table public.orders
  add constraint orders_paid_timestamp_required
  check (payment_status <> 'paid' or paid_at is not null) not valid;
alter table public.orders validate constraint orders_paid_timestamp_required;

create index if not exists orders_paid_at_idx
on public.orders (paid_at desc)
where payment_status = 'paid';

create or replace function public.admin_mark_order_paid(target_order_id uuid)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  previous public.orders%rowtype;
  updated public.orders%rowtype;
begin
  if not public.is_admin() then raise exception 'Admin access required'; end if;

  select * into previous
  from public.orders
  where id = target_order_id
  for update;
  if previous.id is null then raise exception 'Order not found'; end if;

  if previous.payment_method not in ('cash_on_delivery', 'pay_at_store') then
    raise exception 'Only payment collected by staff can be recorded manually';
  end if;
  if previous.order_status in ('cancelled', 'rejected') then
    raise exception 'A closed order cannot be marked paid';
  end if;
  if previous.payment_status = 'paid' then
    return previous.paid_at;
  end if;
  if previous.payment_status <> 'pending' then
    raise exception 'Payment is not pending';
  end if;
  if previous.payment_method = 'pay_at_store'
    and previous.order_status not in ('ready_for_pickup', 'collected') then
    raise exception 'Pickup payment can be recorded only at collection';
  end if;
  if previous.payment_method = 'cash_on_delivery'
    and previous.order_status not in ('out_for_delivery', 'delivered') then
    raise exception 'Delivery payment can be recorded only during delivery';
  end if;

  update public.orders
  set payment_status = 'paid'
  where id = target_order_id
  returning * into updated;

  insert into public.admin_audit_logs (
    admin_id, action, entity_type, entity_id, before_data, after_data
  ) values (
    auth.uid(), 'mark_order_paid', 'order', target_order_id::text,
    pg_catalog.jsonb_build_object(
      'payment_status', previous.payment_status,
      'paid_at', previous.paid_at
    ),
    pg_catalog.jsonb_build_object(
      'payment_status', updated.payment_status,
      'paid_at', updated.paid_at
    )
  );

  return updated.paid_at;
end;
$$;

revoke all on function public.admin_mark_order_paid(uuid)
from public, anon, authenticated;
grant execute on function public.admin_mark_order_paid(uuid)
to authenticated;

revoke all on function public.snapshot_order_contacts()
from public, anon, authenticated;
revoke all on function public.set_order_paid_at()
from public, anon, authenticated;
revoke all on function public.require_payment_before_order_completion()
from public, anon, authenticated;

comment on function public.admin_mark_order_paid(uuid) is
  'MFA-admin-only, audited receipt of cash or pay-at-store payment at collection time.';
