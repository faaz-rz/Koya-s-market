-- Production-safe manual inventory controls and live storefront refresh.

create or replace function public.sync_product_availability()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.available := new.active and new.stock_quantity > 0;
  return new;
end;
$$;

drop trigger if exists products_sync_availability on public.products;
create trigger products_sync_availability
before insert or update of stock_quantity, active on public.products
for each row execute function public.sync_product_availability();

-- Repair any availability values that became stale after order placement or
-- cancellation before the synchronizing trigger existed.
update public.products
set available = active and stock_quantity > 0
where available is distinct from (active and stock_quantity > 0);

create index if not exists products_admin_stock_idx
on public.products (stock_quantity, category_id)
where active;

create or replace function public.admin_set_product_stock(
  target_product_id uuid,
  requested_stock integer
) returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  previous public.products%rowtype;
begin
  if not public.is_admin() then raise exception 'Admin access required'; end if;
  if requested_stock < 0 or requested_stock > 999999 then
    raise exception 'Stock must be between 0 and 999999';
  end if;

  select * into previous
  from public.products
  where id = target_product_id
  for update;
  if previous.id is null then raise exception 'Product not found'; end if;

  update public.products
  set stock_quantity = requested_stock
  where id = target_product_id;

  insert into public.admin_audit_logs (
    admin_id, action, entity_type, entity_id, before_data, after_data
  ) values (
    auth.uid(), 'set_stock', 'product', target_product_id::text,
    jsonb_build_object('stock_quantity', previous.stock_quantity),
    jsonb_build_object('stock_quantity', requested_stock)
  );

  return requested_stock;
end;
$$;

revoke all on function public.admin_set_product_stock(uuid, integer) from public;
grant execute on function public.admin_set_product_stock(uuid, integer) to authenticated;

create or replace function public.admin_adjust_product_stock(
  target_product_id uuid,
  stock_delta integer
) returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  previous public.products%rowtype;
  adjusted_stock integer;
begin
  if not public.is_admin() then raise exception 'Admin access required'; end if;
  if stock_delta < -1000 or stock_delta > 1000 or stock_delta = 0 then
    raise exception 'Invalid stock adjustment';
  end if;

  select * into previous
  from public.products
  where id = target_product_id
  for update;
  if previous.id is null then raise exception 'Product not found'; end if;

  adjusted_stock := previous.stock_quantity + stock_delta;
  if adjusted_stock < 0 or adjusted_stock > 999999 then
    raise exception 'Stock adjustment is outside the allowed range';
  end if;

  update public.products
  set stock_quantity = adjusted_stock
  where id = target_product_id;

  insert into public.admin_audit_logs (
    admin_id, action, entity_type, entity_id, before_data, after_data
  ) values (
    auth.uid(), 'adjust_stock', 'product', target_product_id::text,
    jsonb_build_object('stock_quantity', previous.stock_quantity),
    jsonb_build_object(
      'stock_quantity', adjusted_stock,
      'delta', stock_delta
    )
  );

  return adjusted_stock;
end;
$$;

revoke all on function public.admin_adjust_product_stock(uuid, integer) from public;
grant execute on function public.admin_adjust_product_stock(uuid, integer) to authenticated;

-- Supabase creates this publication. Add only the tables required for live
-- catalogue availability and order-dashboard refreshes.
do $$
begin
  if exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) and not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'products'
  ) then
    alter publication supabase_realtime add table public.products;
  end if;

  if exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) and not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'orders'
  ) then
    alter publication supabase_realtime add table public.orders;
  end if;
end;
$$;
