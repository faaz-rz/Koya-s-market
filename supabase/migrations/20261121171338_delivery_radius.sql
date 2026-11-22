-- The store listing's map pin on Bapu Ghat Road is the delivery origin.
-- Keep the origin in store settings so checkout and sync_store use the same point.
alter table public.store_settings
  add column delivery_origin_latitude double precision not null default 17.37601003
    check (delivery_origin_latitude between -90 and 90),
  add column delivery_origin_longitude double precision not null default 78.41978797
    check (delivery_origin_longitude between -180 and 180);

create function koyas_private.delivery_distance_meters(
  origin_latitude double precision, origin_longitude double precision,
  pin_latitude double precision, pin_longitude double precision
) returns double precision
language sql immutable strict set search_path = ''
as $$
  select 2 * 6371008.8 * asin(sqrt(least(1.0,
    power(sin(radians(pin_latitude - origin_latitude) / 2), 2)
    + cos(radians(origin_latitude)) * cos(radians(pin_latitude))
      * power(sin(radians(pin_longitude - origin_longitude) / 2), 2)
  )));
$$;
revoke all on function koyas_private.delivery_distance_meters(
  double precision, double precision, double precision, double precision
) from public, anon, authenticated;

-- Keep the existing checkout transaction and grants. The outer RPC returns
-- matching idempotency receipts before invoking this check for a new order.
-- The 0.1-micrometre allowance absorbs floating-point roundoff at 5,000 m.
create or replace function public.place_order_internal(
  requested_items jsonb,
  requested_fulfilment public.fulfilment_type,
  requested_address_id uuid,
  requested_date date,
  requested_slot_id uuid,
  requested_payment public.payment_method,
  requested_instructions text,
  requested_idempotency_key text
) returns uuid
language plpgsql security definer set search_path = ''
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
    where id = requested_address_id and user_id = auth.uid()
    for share;
    if selected_address.id is null then raise exception 'Invalid address'; end if;
    if selected_address.delivery_pin is null then
      raise sqlstate 'PT422' using message = 'A delivery pin is required';
    end if;
    if koyas_private.delivery_distance_meters(
      settings.delivery_origin_latitude, settings.delivery_origin_longitude,
      (selected_address.delivery_pin->>'latitude')::double precision,
      (selected_address.delivery_pin->>'longitude')::double precision
    ) > 5000.0000001 then
      raise sqlstate 'PT422' using message = 'Delivery pin is outside the 5 km radius';
    end if;
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
revoke all on function public.place_order_internal(
  jsonb, public.fulfilment_type, uuid, date, uuid, public.payment_method, text, text
) from public, anon, authenticated;

notify pgrst, 'reload schema';
