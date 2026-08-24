-- Remove customer-facing pickup windows and reduce pickup fulfilment to
-- received -> ready for pickup -> collected.
update public.fulfilment_slots
set label = 'Store hours', start_time = '08:00', end_time = '21:00',
    max_orders = 500, sort_order = 1, active = true
where id = '30000000-0000-4000-8000-000000000001';

update public.fulfilment_slots
set active = false
where fulfilment_type = 'pickup'
  and id <> '30000000-0000-4000-8000-000000000001';

create or replace function public.update_order_status(
  target_order_id uuid, next_status public.order_status,
  ready_at timestamptz default null, delivery_name text default null,
  delivery_phone text default null
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
    delivery_contact_name = left(delivery_name, 120),
    delivery_contact_phone = left(delivery_phone, 40)
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
  insert into public.admin_audit_logs (
    admin_id, action, entity_type, entity_id, before_data, after_data
  ) values (
    auth.uid(), 'update_status', 'order', target_order_id::text,
    jsonb_build_object('status', previous.order_status),
    jsonb_build_object('status', next_status)
  );
end;
$$;

revoke all on function public.update_order_status(
  uuid, public.order_status, timestamptz, text, text
) from public;
grant execute on function public.update_order_status(
  uuid, public.order_status, timestamptz, text, text
) to authenticated;

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
