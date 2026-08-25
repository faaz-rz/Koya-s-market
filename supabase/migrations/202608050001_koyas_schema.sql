-- Koya Stores: compact production schema for Supabase/PostgreSQL.
create extension if not exists pgcrypto;

create type public.fulfilment_type as enum ('pickup', 'delivery');
create type public.payment_method as enum ('cash_on_delivery', 'pay_at_store', 'online');
create type public.payment_status as enum ('pending', 'paid', 'failed', 'cancelled', 'refunded');
create type public.order_status as enum (
  'placed', 'confirmed', 'preparing', 'ready_for_pickup', 'collected',
  'ready_for_dispatch', 'out_for_delivery', 'delivered', 'cancelled', 'rejected'
);

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  phone text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.categories (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  image_path text,
  sort_order integer not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.products (
  id uuid primary key default gen_random_uuid(),
  category_id uuid not null references public.categories(id),
  name text not null,
  description text not null default '',
  unit text not null,
  price_paise integer not null check (price_paise >= 0),
  discount_price_paise integer check (
    discount_price_paise is null or
    (discount_price_paise >= 0 and discount_price_paise < price_paise)
  ),
  stock_quantity integer not null default 0 check (stock_quantity >= 0),
  available boolean not null default true,
  active boolean not null default true,
  featured boolean not null default false,
  image_path text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index products_catalog_idx on public.products(category_id, active, available);
create index products_name_search_idx on public.products using gin(to_tsvector('simple', name));

create table public.addresses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  label text not null,
  recipient_name text not null,
  phone text not null,
  line1 text not null,
  city text not null,
  pincode text not null check (pincode ~ '^\d{6}$'),
  instructions text not null default '',
  is_default boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index addresses_user_idx on public.addresses(user_id);

create table public.store_settings (
  id smallint primary key default 1 check (id = 1),
  store_name text not null default 'Koya Stores',
  store_address text not null,
  contact_phone text not null,
  opening_hours text not null,
  minimum_order_paise integer not null default 19900 check (minimum_order_paise >= 0),
  delivery_charge_paise integer not null default 4900 check (delivery_charge_paise >= 0),
  free_delivery_threshold_paise integer not null default 79900 check (free_delivery_threshold_paise >= 0),
  cash_on_delivery_enabled boolean not null default true,
  delivery_enabled boolean not null default true,
  pickup_enabled boolean not null default true,
  updated_at timestamptz not null default now()
);
insert into public.store_settings (
  store_address, contact_phone, opening_hours
) values (
  'Road No. 12, Banjara Hills, Hyderabad', '+91 40 4000 2020', '8:00 AM – 9:00 PM'
) on conflict (id) do nothing;

create table public.serviceable_pincodes (
  pincode text primary key check (pincode ~ '^\d{6}$'),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.fulfilment_slots (
  id uuid primary key default gen_random_uuid(),
  fulfilment_type public.fulfilment_type not null,
  label text not null,
  start_time time not null,
  end_time time not null,
  max_orders integer not null default 20 check (max_orders > 0),
  active boolean not null default true,
  sort_order integer not null default 0,
  unique (fulfilment_type, start_time, end_time)
);

create table public.banners (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  subtitle text not null default '',
  image_path text,
  deep_link text,
  starts_at timestamptz,
  ends_at timestamptz,
  active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at is null or starts_at is null or ends_at > starts_at)
);

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  order_number bigint generated always as identity unique,
  user_id uuid not null references auth.users(id),
  fulfilment_type public.fulfilment_type not null,
  address_id uuid references public.addresses(id) on delete set null,
  delivery_address_text text,
  fulfilment_date date not null,
  slot_id uuid not null references public.fulfilment_slots(id),
  slot_label text not null,
  subtotal_paise integer not null check (subtotal_paise >= 0),
  delivery_charge_paise integer not null default 0 check (delivery_charge_paise >= 0),
  discount_paise integer not null default 0 check (discount_paise >= 0),
  total_paise integer not null check (total_paise >= 0),
  payment_method public.payment_method not null,
  payment_status public.payment_status not null default 'pending',
  order_status public.order_status not null default 'placed',
  delivery_instructions text not null default '',
  delivery_contact_name text,
  delivery_contact_phone text,
  estimated_ready_at timestamptz,
  cancellation_reason text,
  idempotency_key text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, idempotency_key),
  check (
    (fulfilment_type = 'pickup' and address_id is null and delivery_address_text is null) or
    (fulfilment_type = 'delivery' and delivery_address_text is not null)
  )
);
create index orders_user_created_idx on public.orders(user_id, created_at desc);
create index orders_admin_queue_idx on public.orders(order_status, created_at desc);
create index orders_slot_capacity_idx on public.orders(slot_id, fulfilment_date);

create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  product_id uuid references public.products(id),
  product_name text not null,
  unit text not null,
  unit_price_paise integer not null check (unit_price_paise >= 0),
  quantity integer not null check (quantity > 0),
  total_paise integer generated always as (unit_price_paise * quantity) stored,
  image_path text
);
create index order_items_order_idx on public.order_items(order_id);

create table public.payment_events (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  provider text not null default 'razorpay',
  provider_order_id text,
  provider_payment_id text,
  event_type text not null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (provider, provider_payment_id, event_type)
);
create unique index payment_order_once_idx on public.payment_events(order_id, event_type)
where event_type = 'order_created';

create table public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  token text not null unique,
  platform text not null check (platform in ('android', 'ios', 'web')),
  updated_at timestamptz not null default now()
);

create table public.notification_queue (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  order_id uuid references public.orders(id) on delete cascade,
  title text not null,
  body text not null,
  data jsonb not null default '{}'::jsonb,
  processed_at timestamptz,
  attempts integer not null default 0,
  created_at timestamptz not null default now()
);

create table public.admin_audit_logs (
  id bigint generated always as identity primary key,
  admin_id uuid not null references auth.users(id),
  action text not null,
  entity_type text not null,
  entity_id text not null,
  before_data jsonb,
  after_data jsonb,
  created_at timestamptz not null default now()
);

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.admins
    where user_id = auth.uid() and active = true
  );
$$;

create or replace function public.set_updated_at()
returns trigger language plpgsql set search_path = public as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_updated_at before update on public.profiles
for each row execute function public.set_updated_at();
create trigger categories_updated_at before update on public.categories
for each row execute function public.set_updated_at();
create trigger products_updated_at before update on public.products
for each row execute function public.set_updated_at();
create trigger addresses_updated_at before update on public.addresses
for each row execute function public.set_updated_at();
create trigger banners_updated_at before update on public.banners
for each row execute function public.set_updated_at();
create trigger orders_updated_at before update on public.orders
for each row execute function public.set_updated_at();

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, full_name, phone)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    new.phone
  );
  return new;
end;
$$;
create trigger on_auth_user_created
after insert on auth.users for each row execute function public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.admins enable row level security;
alter table public.categories enable row level security;
alter table public.products enable row level security;
alter table public.addresses enable row level security;
alter table public.store_settings enable row level security;
alter table public.serviceable_pincodes enable row level security;
alter table public.fulfilment_slots enable row level security;
alter table public.banners enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.payment_events enable row level security;
alter table public.device_tokens enable row level security;
alter table public.notification_queue enable row level security;
alter table public.admin_audit_logs enable row level security;

create policy profiles_own_read on public.profiles for select
using (id = auth.uid() or public.is_admin());
create policy profiles_own_update on public.profiles for update
using (id = auth.uid()) with check (id = auth.uid());
create policy admins_self_read on public.admins for select
using (user_id = auth.uid());

create policy categories_public_read on public.categories for select
using (active or public.is_admin());
create policy categories_admin_write on public.categories for all
using (public.is_admin()) with check (public.is_admin());
create policy products_public_read on public.products for select
using (active or public.is_admin());
create policy products_admin_write on public.products for all
using (public.is_admin()) with check (public.is_admin());
create policy banners_public_read on public.banners for select
using (
  public.is_admin() or
  (active and (starts_at is null or starts_at <= now()) and (ends_at is null or ends_at > now()))
);
create policy banners_admin_write on public.banners for all
using (public.is_admin()) with check (public.is_admin());

create policy settings_authenticated_read on public.store_settings for select
to authenticated using (true);
create policy settings_admin_write on public.store_settings for all
using (public.is_admin()) with check (public.is_admin());
create policy pincodes_authenticated_read on public.serviceable_pincodes for select
to authenticated using (active or public.is_admin());
create policy pincodes_admin_write on public.serviceable_pincodes for all
using (public.is_admin()) with check (public.is_admin());
create policy slots_authenticated_read on public.fulfilment_slots for select
to authenticated using (active or public.is_admin());
create policy slots_admin_write on public.fulfilment_slots for all
using (public.is_admin()) with check (public.is_admin());

create policy addresses_own_all on public.addresses for all
using (user_id = auth.uid() or public.is_admin())
with check (user_id = auth.uid() or public.is_admin());
create policy orders_own_read on public.orders for select
using (user_id = auth.uid() or public.is_admin());
create policy order_items_own_read on public.order_items for select
using (
  public.is_admin() or exists (
    select 1 from public.orders where orders.id = order_id and orders.user_id = auth.uid()
  )
);
create policy device_tokens_own_all on public.device_tokens for all
using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy notification_own_read on public.notification_queue for select
using (user_id = auth.uid() or public.is_admin());
create policy payment_events_admin_read on public.payment_events for select
using (public.is_admin());
create policy audit_admin_read on public.admin_audit_logs for select
using (public.is_admin());

create or replace function public.place_order(
  requested_items jsonb,
  requested_fulfilment public.fulfilment_type,
  requested_address_id uuid,
  requested_date date,
  requested_slot_id uuid,
  requested_payment public.payment_method,
  requested_instructions text,
  requested_idempotency_key text
) returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  settings public.store_settings%rowtype;
  selected_address public.addresses%rowtype;
  selected_slot public.fulfilment_slots%rowtype;
  line record;
  product_row public.products%rowtype;
  existing_order_id uuid;
  created_order_id uuid;
  subtotal integer := 0;
  calculated_discount integer := 0;
  delivery_charge integer := 0;
  final_total integer := 0;
  order_count integer := 0;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if requested_items is null or jsonb_array_length(requested_items) = 0 then
    raise exception 'Cart is empty';
  end if;
  if length(requested_idempotency_key) < 8 then
    raise exception 'Invalid idempotency key';
  end if;
  if requested_date < current_date or requested_date > current_date + 14 then
    raise exception 'Invalid fulfilment date';
  end if;

  select id into existing_order_id from public.orders
  where user_id = auth.uid() and idempotency_key = requested_idempotency_key;
  if existing_order_id is not null then return existing_order_id; end if;

  select * into settings from public.store_settings where id = 1;
  if requested_fulfilment = 'pickup' and not settings.pickup_enabled then
    raise exception 'Pickup is currently unavailable';
  end if;
  if requested_fulfilment = 'delivery' and not settings.delivery_enabled then
    raise exception 'Delivery is currently unavailable';
  end if;

  select * into selected_slot from public.fulfilment_slots
  where id = requested_slot_id and active and fulfilment_type = requested_fulfilment
  for update;
  if selected_slot.id is null then raise exception 'Invalid fulfilment slot'; end if;
  select count(*) into order_count from public.orders
  where slot_id = requested_slot_id and fulfilment_date = requested_date
    and order_status not in ('cancelled', 'rejected');
  if order_count >= selected_slot.max_orders then raise exception 'This slot is full'; end if;

  if requested_fulfilment = 'delivery' then
    select * into selected_address from public.addresses
    where id = requested_address_id and user_id = auth.uid();
    if selected_address.id is null then raise exception 'Invalid address'; end if;
    if not exists (
      select 1 from public.serviceable_pincodes
      where pincode = selected_address.pincode and active
    ) then raise exception 'Address is outside the service area'; end if;
    if requested_payment = 'pay_at_store' then raise exception 'Invalid payment method'; end if;
    if requested_payment = 'cash_on_delivery' and not settings.cash_on_delivery_enabled then
      raise exception 'Cash on delivery is unavailable';
    end if;
  else
    requested_address_id := null;
    if requested_payment = 'cash_on_delivery' then raise exception 'Invalid payment method'; end if;
  end if;

  for line in
    select product_id, sum(quantity)::integer as quantity
    from jsonb_to_recordset(requested_items) as x(product_id uuid, quantity integer)
    group by product_id
    order by product_id
  loop
    if line.quantity <= 0 or line.quantity > 99 then raise exception 'Invalid quantity'; end if;
    select * into product_row from public.products
    where id = line.product_id for update;
    if product_row.id is null or not product_row.active or not product_row.available then
      raise exception 'A product is unavailable';
    end if;
    if product_row.stock_quantity < line.quantity then raise exception 'Insufficient stock'; end if;
    subtotal := subtotal + coalesce(product_row.discount_price_paise, product_row.price_paise) * line.quantity;
    calculated_discount := calculated_discount +
      (product_row.price_paise - coalesce(product_row.discount_price_paise, product_row.price_paise)) * line.quantity;
  end loop;

  if subtotal < settings.minimum_order_paise then raise exception 'Minimum order amount not reached'; end if;
  if requested_fulfilment = 'delivery' and subtotal < settings.free_delivery_threshold_paise then
    delivery_charge := settings.delivery_charge_paise;
  end if;
  final_total := subtotal + delivery_charge;

  insert into public.orders (
    user_id, fulfilment_type, address_id, delivery_address_text, fulfilment_date, slot_id, slot_label,
    subtotal_paise, delivery_charge_paise, discount_paise, total_paise,
    payment_method, payment_status, delivery_instructions, idempotency_key
  ) values (
    auth.uid(), requested_fulfilment, requested_address_id,
    case when requested_fulfilment = 'delivery' then
      selected_address.line1 || ', ' || selected_address.city || ' – ' || selected_address.pincode
    else null end,
    requested_date,
    requested_slot_id, selected_slot.label, subtotal, delivery_charge, calculated_discount,
    final_total, requested_payment, 'pending', left(coalesce(requested_instructions, ''), 500),
    requested_idempotency_key
  ) returning id into created_order_id;

  for line in
    select product_id, sum(quantity)::integer as quantity
    from jsonb_to_recordset(requested_items) as x(product_id uuid, quantity integer)
    group by product_id
    order by product_id
  loop
    select * into product_row from public.products where id = line.product_id for update;
    insert into public.order_items (
      order_id, product_id, product_name, unit, unit_price_paise, quantity, image_path
    ) values (
      created_order_id, product_row.id, product_row.name, product_row.unit,
      coalesce(product_row.discount_price_paise, product_row.price_paise), line.quantity,
      product_row.image_path
    );
    update public.products set stock_quantity = stock_quantity - line.quantity
    where id = product_row.id;
  end loop;

  return created_order_id;
end;
$$;
revoke all on function public.place_order(jsonb, public.fulfilment_type, uuid, date, uuid, public.payment_method, text, text) from public;
grant execute on function public.place_order(jsonb, public.fulfilment_type, uuid, date, uuid, public.payment_method, text, text) to authenticated;

create or replace function public.cancel_own_order(target_order_id uuid, reason text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.orders set
    order_status = 'cancelled', cancellation_reason = left(reason, 300)
  where id = target_order_id and user_id = auth.uid()
    and order_status in ('placed', 'confirmed');
  if not found then raise exception 'Order can no longer be cancelled'; end if;
  update public.products product set stock_quantity = product.stock_quantity + restored.quantity
  from (
    select product_id, sum(quantity)::integer as quantity
    from public.order_items where order_id = target_order_id and product_id is not null
    group by product_id
  ) restored
  where product.id = restored.product_id;
end;
$$;
revoke all on function public.cancel_own_order(uuid, text) from public;
grant execute on function public.cancel_own_order(uuid, text) to authenticated;

create or replace function public.update_order_status(
  target_order_id uuid, next_status public.order_status,
  ready_at timestamptz default null, delivery_name text default null, delivery_phone text default null
) returns void language plpgsql security definer set search_path = public as $$
declare previous public.orders%rowtype;
begin
  if not public.is_admin() then raise exception 'Admin access required'; end if;
  select * into previous from public.orders where id = target_order_id for update;
  if previous.id is null then raise exception 'Order not found'; end if;
  if previous.payment_method = 'online' and previous.payment_status <> 'paid'
    and next_status not in ('cancelled', 'rejected') then
    raise exception 'Online payment is not complete';
  end if;
  if not (
    (previous.fulfilment_type = 'pickup' and previous.order_status in ('placed', 'confirmed', 'preparing') and next_status = 'ready_for_pickup') or
    (previous.order_status = 'placed' and next_status in ('confirmed', 'rejected')) or
    (previous.order_status = 'confirmed' and next_status in ('preparing', 'cancelled')) or
    (previous.order_status = 'preparing' and previous.fulfilment_type = 'pickup' and next_status = 'ready_for_pickup') or
    (previous.order_status = 'ready_for_pickup' and next_status = 'collected') or
    (previous.order_status = 'preparing' and previous.fulfilment_type = 'delivery' and next_status = 'ready_for_dispatch') or
    (previous.order_status = 'ready_for_dispatch' and next_status = 'out_for_delivery') or
    (previous.order_status = 'out_for_delivery' and next_status = 'delivered')
  ) then raise exception 'Invalid status transition'; end if;

  update public.orders set order_status = next_status, estimated_ready_at = ready_at,
    delivery_contact_name = left(delivery_name, 120), delivery_contact_phone = left(delivery_phone, 40)
  where id = target_order_id;
  if next_status in ('cancelled', 'rejected') then
    update public.products product set stock_quantity = product.stock_quantity + restored.quantity
    from (
      select product_id, sum(quantity)::integer as quantity
      from public.order_items where order_id = target_order_id and product_id is not null
      group by product_id
    ) restored
    where product.id = restored.product_id;
  end if;
  insert into public.admin_audit_logs (admin_id, action, entity_type, entity_id, before_data, after_data)
  values (auth.uid(), 'update_status', 'order', target_order_id::text,
    jsonb_build_object('status', previous.order_status), jsonb_build_object('status', next_status));
end;
$$;
revoke all on function public.update_order_status(uuid, public.order_status, timestamptz, text, text) from public;
grant execute on function public.update_order_status(uuid, public.order_status, timestamptz, text, text) to authenticated;

create or replace function public.queue_status_notification()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if old.order_status is distinct from new.order_status and (
    new.order_status in ('ready_for_pickup', 'cancelled', 'rejected')
  ) then
    insert into public.notification_queue (user_id, order_id, title, body, data)
    values (
      new.user_id, new.id, 'Order #' || new.order_number,
      case new.order_status
        when 'ready_for_pickup' then 'Your order is ready for pickup'
        when 'cancelled' then 'Your order has been cancelled'
        else 'The store could not fulfil your order'
      end,
      jsonb_build_object('order_id', new.id, 'status', new.order_status)
    );
  end if;
  return new;
end;
$$;
create trigger order_status_notification after update of order_status on public.orders
for each row execute function public.queue_status_notification();

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('product-images', 'product-images', true, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update set file_size_limit = excluded.file_size_limit,
allowed_mime_types = excluded.allowed_mime_types;

create policy product_images_public_read on storage.objects for select
using (bucket_id = 'product-images');
create policy product_images_admin_insert on storage.objects for insert
with check (bucket_id = 'product-images' and public.is_admin());
create policy product_images_admin_update on storage.objects for update
using (bucket_id = 'product-images' and public.is_admin())
with check (bucket_id = 'product-images' and public.is_admin());
create policy product_images_admin_delete on storage.objects for delete
using (bucket_id = 'product-images' and public.is_admin());
