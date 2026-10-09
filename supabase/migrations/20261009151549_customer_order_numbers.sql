set local lock_timeout='5s';
-- Customer-visible numbers are independent of the existing global order number.
-- Counter updates share the order transaction, so a failed checkout rolls back
-- its number. The checkout RPC's per-customer/idempotency lock prevents replay
-- from creating or numbering a second order.
alter table public.orders add column customer_order_number bigint;

with numbered as (
  select id, row_number() over(partition by user_id order by created_at,order_number) as number
  from public.orders where user_id is not null
)
update public.orders o set customer_order_number=n.number, updated_at=clock_timestamp()
from numbered n where o.id=n.id;

create table koyas_private.customer_order_counters (
  user_id uuid primary key references auth.users(id) on delete cascade,
  last_number bigint not null check(last_number>0)
);
alter table koyas_private.customer_order_counters enable row level security;
revoke all on koyas_private.customer_order_counters from public,anon,authenticated,service_role;
insert into koyas_private.customer_order_counters(user_id,last_number)
select user_id,max(customer_order_number) from public.orders
where user_id is not null group by user_id;

alter table public.orders add constraint orders_customer_number_positive
  check(customer_order_number is null or customer_order_number>0),
  add constraint orders_customer_number_required
  check(user_id is null or customer_order_number is not null),
  add constraint orders_customer_number_unique unique(user_id,customer_order_number);

create function koyas_private.assign_customer_order_number()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if tg_op='UPDATE' then
    if new.customer_order_number is distinct from old.customer_order_number then
      raise exception 'An order number cannot be changed';
    end if;
    return new;
  end if;
  if new.user_id is null then raise exception 'A customer is required for a new order'; end if;
  insert into koyas_private.customer_order_counters(user_id,last_number)
  values(new.user_id,1)
  on conflict(user_id) do update
    set last_number=koyas_private.customer_order_counters.last_number+1
  returning last_number into new.customer_order_number;
  return new;
end;
$$;
revoke all on function koyas_private.assign_customer_order_number() from public,anon,authenticated,service_role;
create trigger assign_customer_order_number
before insert or update of customer_order_number on public.orders
for each row execute function koyas_private.assign_customer_order_number();

create or replace function public.queue_status_notification()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if old.order_status is distinct from new.order_status
    and new.user_id is not null
    and new.order_status in ('ready_for_pickup','out_for_delivery','delivered','collected','cancelled','rejected') then
    insert into public.notification_queue(user_id,order_id,title,body,data)
    values(new.user_id,new.id,'Order #' || new.customer_order_number,
      'Order #' || new.customer_order_number || ': ' ||
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
notify pgrst,'reload schema';
