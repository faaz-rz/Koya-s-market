-- Server-authoritative cart offers. Product-level sale prices remain separate;
-- these offers can require a minimum basket, discount the order, add a free
-- product, or combine both benefits.
create table public.offers (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  title text not null,
  description text not null default '',
  minimum_subtotal_paise integer not null default 0,
  discount_type text,
  discount_value integer not null default 0,
  maximum_discount_paise integer,
  free_product_id uuid references public.products(id) on delete restrict,
  free_quantity integer not null default 1,
  required_fulfilment public.fulfilment_type,
  starts_at timestamptz,
  ends_at timestamptz,
  total_redemption_limit integer,
  per_customer_limit integer not null default 1,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (code = upper(code) and code ~ '^[A-Z0-9_-]{3,24}$'),
  check (length(title) between 2 and 120),
  check (length(description) <= 500),
  check (minimum_subtotal_paise between 0 and 100000000),
  check (
    (discount_type is null and discount_value = 0) or
    (discount_type = 'flat' and discount_value between 1 and 100000000) or
    (discount_type = 'percentage' and discount_value between 1 and 100)
  ),
  check (
    maximum_discount_paise is null or
    maximum_discount_paise between 1 and 100000000
  ),
  check (discount_type is not null or free_product_id is not null),
  check (free_quantity between 1 and 20),
  check (ends_at is null or starts_at is null or ends_at > starts_at),
  check (
    total_redemption_limit is null or
    total_redemption_limit between 1 and 10000000
  ),
  check (per_customer_limit between 1 and 10000)
);

create index offers_customer_visible_idx
on public.offers (active, starts_at, ends_at);

create trigger offers_updated_at
before update on public.offers
for each row execute function public.set_updated_at();

alter table public.orders
  add column if not exists applied_offer_id uuid
    references public.offers(id) on delete set null,
  add column if not exists applied_offer_code text,
  add column if not exists applied_offer_title text,
  add column if not exists offer_discount_paise integer not null default 0
    check (offer_discount_paise >= 0);

alter table public.order_items
  add column if not exists is_free_offer_item boolean not null default false;

create table public.offer_redemptions (
  id bigint generated always as identity primary key,
  offer_id uuid not null references public.offers(id) on delete restrict,
  order_id uuid not null unique references public.orders(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  offer_code_snapshot text not null,
  discount_paise integer not null default 0 check (discount_paise >= 0),
  free_product_id uuid references public.products(id) on delete set null,
  free_quantity integer not null default 0 check (free_quantity between 0 and 20),
  created_at timestamptz not null default now(),
  unique (offer_id, order_id)
);

create index offer_redemptions_offer_idx
on public.offer_redemptions (offer_id, created_at desc);
create index offer_redemptions_customer_idx
on public.offer_redemptions (offer_id, user_id, created_at desc);

alter table public.offers enable row level security;
alter table public.offer_redemptions enable row level security;

create policy offers_customer_or_admin_read
on public.offers for select to authenticated
using (
  public.is_admin() or (
    active
    and (starts_at is null or starts_at <= now())
    and (ends_at is null or ends_at > now())
  )
);

create policy offer_redemptions_own_or_admin_read
on public.offer_redemptions for select to authenticated
using (user_id = auth.uid() or public.is_admin());

create or replace function public.admin_save_offer(
  target_offer_id uuid,
  requested_code text,
  requested_title text,
  requested_description text,
  requested_minimum_subtotal_paise integer,
  requested_discount_type text,
  requested_discount_value integer,
  requested_maximum_discount_paise integer,
  requested_free_product_id uuid,
  requested_free_quantity integer,
  requested_fulfilment public.fulfilment_type,
  requested_starts_at timestamptz,
  requested_ends_at timestamptz,
  requested_total_redemption_limit integer,
  requested_per_customer_limit integer,
  requested_active boolean
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized_code text := pg_catalog.upper(
    pg_catalog.btrim(coalesce(requested_code, ''))
  );
  normalized_title text := pg_catalog.btrim(coalesce(requested_title, ''));
  previous public.offers%rowtype;
  updated public.offers%rowtype;
begin
  if not public.is_admin() then raise exception 'Admin access required'; end if;
  if normalized_code !~ '^[A-Z0-9_-]{3,24}$' then
    raise exception 'Offer code must contain 3 to 24 letters, numbers, dashes, or underscores';
  end if;
  if pg_catalog.length(normalized_title) not between 2 and 120 then
    raise exception 'Offer title must contain 2 to 120 characters';
  end if;
  if pg_catalog.length(coalesce(requested_description, '')) > 500 then
    raise exception 'Offer description is too long';
  end if;
  if requested_minimum_subtotal_paise is null
    or requested_minimum_subtotal_paise not between 0 and 100000000 then
    raise exception 'Minimum basket amount is invalid';
  end if;
  if requested_discount_type is not null
    and requested_discount_type not in ('flat', 'percentage') then
    raise exception 'Discount type is invalid';
  end if;
  if requested_discount_type = 'flat'
    and requested_discount_value not between 1 and 100000000 then
    raise exception 'Flat discount is invalid';
  end if;
  if requested_discount_type = 'percentage'
    and requested_discount_value not between 1 and 100 then
    raise exception 'Percentage discount must be between 1 and 100';
  end if;
  if requested_discount_type is null
    and coalesce(requested_discount_value, 0) <> 0 then
    raise exception 'Discount value requires a discount type';
  end if;
  if requested_maximum_discount_paise is not null and (
    requested_discount_type is distinct from 'percentage'
    or requested_maximum_discount_paise not between 1 and 100000000
  ) then
    raise exception 'Maximum discount is invalid';
  end if;
  if requested_free_product_id is null and requested_discount_type is null then
    raise exception 'Choose a discount, a free product, or both';
  end if;
  if requested_free_quantity is null
    or requested_free_quantity not between 1 and 20 then
    raise exception 'Free quantity must be between 1 and 20';
  end if;
  if requested_free_product_id is not null and not exists (
    select 1 from public.products
    where id = requested_free_product_id
  ) then
    raise exception 'Free product was not found';
  end if;
  if requested_ends_at is not null and requested_starts_at is not null
    and requested_ends_at <= requested_starts_at then
    raise exception 'Offer end must be after its start';
  end if;
  if requested_total_redemption_limit is not null
    and requested_total_redemption_limit not between 1 and 10000000 then
    raise exception 'Total redemption limit is invalid';
  end if;
  if requested_per_customer_limit is null
    or requested_per_customer_limit not between 1 and 10000 then
    raise exception 'Per-customer limit is invalid';
  end if;
  if requested_active is null then raise exception 'Active state is required'; end if;

  if exists (
    select 1 from public.offers
    where code = normalized_code
      and id is distinct from target_offer_id
  ) then
    raise exception 'Offer code already exists';
  end if;

  if target_offer_id is null then
    insert into public.offers (
      code, title, description, minimum_subtotal_paise,
      discount_type, discount_value, maximum_discount_paise,
      free_product_id, free_quantity, required_fulfilment,
      starts_at, ends_at, total_redemption_limit, per_customer_limit, active
    ) values (
      normalized_code, normalized_title,
      pg_catalog.btrim(coalesce(requested_description, '')),
      requested_minimum_subtotal_paise,
      requested_discount_type, coalesce(requested_discount_value, 0),
      requested_maximum_discount_paise,
      requested_free_product_id, requested_free_quantity,
      requested_fulfilment, requested_starts_at, requested_ends_at,
      requested_total_redemption_limit, requested_per_customer_limit,
      requested_active
    ) returning * into updated;
  else
    select * into previous
    from public.offers
    where id = target_offer_id
    for update;
    if previous.id is null then raise exception 'Offer not found'; end if;

    update public.offers
    set code = normalized_code,
        title = normalized_title,
        description = pg_catalog.btrim(coalesce(requested_description, '')),
        minimum_subtotal_paise = requested_minimum_subtotal_paise,
        discount_type = requested_discount_type,
        discount_value = coalesce(requested_discount_value, 0),
        maximum_discount_paise = requested_maximum_discount_paise,
        free_product_id = requested_free_product_id,
        free_quantity = requested_free_quantity,
        required_fulfilment = requested_fulfilment,
        starts_at = requested_starts_at,
        ends_at = requested_ends_at,
        total_redemption_limit = requested_total_redemption_limit,
        per_customer_limit = requested_per_customer_limit,
        active = requested_active
    where id = target_offer_id
    returning * into updated;
  end if;

  insert into public.admin_audit_logs (
    admin_id, action, entity_type, entity_id, before_data, after_data
  ) values (
    auth.uid(),
    case when target_offer_id is null then 'create_offer' else 'update_offer' end,
    'offer', updated.id::text, to_jsonb(previous), to_jsonb(updated)
  );

  return updated.id;
end;
$$;

create or replace function public.place_order_v2(
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
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  normalized_offer_code text := nullif(
    pg_catalog.upper(pg_catalog.btrim(coalesce(requested_offer_code, ''))),
    ''
  );
  existing_order public.orders%rowtype;
  created_order public.orders%rowtype;
  selected_offer public.offers%rowtype;
  free_product public.products%rowtype;
  created_order_id uuid;
  calculated_offer_discount integer := 0;
  total_redemptions integer := 0;
  customer_redemptions integer := 0;
begin
  if current_user_id is null then raise exception 'Authentication required'; end if;
  if normalized_offer_code is not null
    and normalized_offer_code !~ '^[A-Z0-9_-]{3,24}$' then
    raise exception 'Offer code is invalid';
  end if;

  -- Serialize idempotency checks with the underlying placement function.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(current_user_id::text, 0)
  );
  select * into existing_order
  from public.orders
  where user_id = current_user_id
    and idempotency_key = requested_idempotency_key;
  if existing_order.id is not null then
    if coalesce(existing_order.applied_offer_code, '')
      <> coalesce(normalized_offer_code, '') then
      raise exception 'Idempotency key was already used with a different offer';
    end if;
    return existing_order.id;
  end if;

  created_order_id := public.place_order(
    requested_items,
    requested_fulfilment,
    requested_address_id,
    requested_date,
    requested_slot_id,
    requested_payment,
    requested_instructions,
    requested_idempotency_key
  );

  if normalized_offer_code is null then return created_order_id; end if;

  select * into created_order
  from public.orders
  where id = created_order_id
    and user_id = current_user_id
  for update;

  -- Locking the offer serializes limit checks and prevents over-redemption.
  select * into selected_offer
  from public.offers
  where code = normalized_offer_code
  for update;
  if selected_offer.id is null then raise exception 'Offer code was not found'; end if;
  if not selected_offer.active
    or (selected_offer.starts_at is not null and selected_offer.starts_at > now())
    or (selected_offer.ends_at is not null and selected_offer.ends_at <= now()) then
    raise exception 'Offer is not active';
  end if;
  if selected_offer.required_fulfilment is not null
    and selected_offer.required_fulfilment <> created_order.fulfilment_type then
    raise exception 'Offer is not valid for this fulfilment method';
  end if;
  if created_order.subtotal_paise < selected_offer.minimum_subtotal_paise then
    raise exception 'Minimum basket amount for this offer was not reached';
  end if;

  select pg_catalog.count(*) into total_redemptions
  from public.offer_redemptions as redemption
  join public.orders as redeemed_order on redeemed_order.id = redemption.order_id
  where redemption.offer_id = selected_offer.id
    and redeemed_order.order_status not in ('cancelled', 'rejected');
  if selected_offer.total_redemption_limit is not null
    and total_redemptions >= selected_offer.total_redemption_limit then
    raise exception 'Offer redemption limit has been reached';
  end if;

  select pg_catalog.count(*) into customer_redemptions
  from public.offer_redemptions as redemption
  join public.orders as redeemed_order on redeemed_order.id = redemption.order_id
  where redemption.offer_id = selected_offer.id
    and redemption.user_id = current_user_id
    and redeemed_order.order_status not in ('cancelled', 'rejected');
  if customer_redemptions >= selected_offer.per_customer_limit then
    raise exception 'You have already used this offer';
  end if;

  if selected_offer.discount_type = 'flat' then
    calculated_offer_discount := least(
      selected_offer.discount_value,
      created_order.subtotal_paise
    );
  elsif selected_offer.discount_type = 'percentage' then
    calculated_offer_discount := (
      created_order.subtotal_paise::bigint * selected_offer.discount_value / 100
    )::integer;
    if selected_offer.maximum_discount_paise is not null then
      calculated_offer_discount := least(
        calculated_offer_discount,
        selected_offer.maximum_discount_paise
      );
    end if;
  end if;

  if selected_offer.free_product_id is not null then
    select * into free_product
    from public.products
    where id = selected_offer.free_product_id
    for update;
    if free_product.id is null
      or not free_product.active
      or not free_product.available
      or free_product.stock_quantity < selected_offer.free_quantity then
      raise exception 'The free product is currently unavailable';
    end if;

    insert into public.order_items (
      order_id, product_id, product_name, unit, unit_price_paise,
      quantity, image_path, is_free_offer_item
    ) values (
      created_order_id, free_product.id, free_product.name, free_product.unit,
      0, selected_offer.free_quantity, free_product.image_path, true
    );
    update public.products
    set stock_quantity = stock_quantity - selected_offer.free_quantity
    where id = free_product.id;
  end if;

  update public.orders
  set applied_offer_id = selected_offer.id,
      applied_offer_code = selected_offer.code,
      applied_offer_title = selected_offer.title,
      offer_discount_paise = calculated_offer_discount,
      discount_paise = discount_paise + calculated_offer_discount,
      total_paise = greatest(0, total_paise - calculated_offer_discount)
  where id = created_order_id;

  insert into public.offer_redemptions (
    offer_id, order_id, user_id, offer_code_snapshot, discount_paise,
    free_product_id, free_quantity
  ) values (
    selected_offer.id, created_order_id, current_user_id, selected_offer.code,
    calculated_offer_discount, selected_offer.free_product_id,
    case when selected_offer.free_product_id is null
      then 0 else selected_offer.free_quantity end
  );

  return created_order_id;
end;
$$;

revoke all on function public.admin_save_offer(
  uuid, text, text, text, integer, text, integer, integer, uuid, integer,
  public.fulfilment_type, timestamptz, timestamptz, integer, integer, boolean
) from public, anon, authenticated;
grant execute on function public.admin_save_offer(
  uuid, text, text, text, integer, text, integer, integer, uuid, integer,
  public.fulfilment_type, timestamptz, timestamptz, integer, integer, boolean
) to authenticated;

revoke all on function public.place_order(
  jsonb, public.fulfilment_type, uuid, date, uuid,
  public.payment_method, text, text
) from public, anon, authenticated;
revoke all on function public.place_order_v2(
  jsonb, public.fulfilment_type, uuid, date, uuid,
  public.payment_method, text, text, text
) from public, anon, authenticated;
grant execute on function public.place_order_v2(
  jsonb, public.fulfilment_type, uuid, date, uuid,
  public.payment_method, text, text, text
) to authenticated;

do $$
begin
  if exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) and not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'offers'
  ) then
    alter publication supabase_realtime add table public.offers;
  end if;
end;
$$;
