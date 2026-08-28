-- Start without a minimum order and let MFA-authenticated staff decide whether
-- to introduce one. Order placement already reads this setting atomically, so
-- zero disables the minimum while a positive value is enforced server-side.
update public.store_settings
set minimum_order_paise = 0,
    updated_at = now()
where id = 1;

drop function if exists public.admin_update_delivery_pricing(integer, integer);

create or replace function public.admin_update_order_pricing(
  requested_minimum_order_paise integer,
  requested_delivery_charge_paise integer,
  requested_free_delivery_threshold_paise integer
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  previous public.store_settings%rowtype;
  updated public.store_settings%rowtype;
begin
  if not public.is_admin() then raise exception 'Admin access required'; end if;

  if requested_minimum_order_paise is null or
     requested_minimum_order_paise < 0 or
     requested_minimum_order_paise > 100000000 then
    raise exception 'Minimum order is outside the allowed range';
  end if;
  if requested_delivery_charge_paise is null or
     requested_delivery_charge_paise < 0 or
     requested_delivery_charge_paise > 1000000 then
    raise exception 'Delivery charge must be between 0 and 1000000 paise';
  end if;
  if requested_free_delivery_threshold_paise is null or
     requested_free_delivery_threshold_paise < 0 or
     requested_free_delivery_threshold_paise > 100000000 then
    raise exception 'Free delivery threshold is outside the allowed range';
  end if;

  select * into previous
  from public.store_settings
  where id = 1
  for update;
  if previous.id is null then raise exception 'Store settings not found'; end if;

  update public.store_settings
  set minimum_order_paise = requested_minimum_order_paise,
      delivery_charge_paise = requested_delivery_charge_paise,
      free_delivery_threshold_paise = requested_free_delivery_threshold_paise,
      updated_at = now()
  where id = 1
  returning * into updated;

  insert into public.admin_audit_logs (
    admin_id, action, entity_type, entity_id, before_data, after_data
  ) values (
    auth.uid(), 'update_order_pricing', 'store_settings', '1',
    to_jsonb(previous), to_jsonb(updated)
  );
end;
$$;

revoke all on function public.admin_update_order_pricing(integer, integer, integer)
from public, anon, authenticated;
grant execute on function public.admin_update_order_pricing(integer, integer, integer)
to authenticated;
