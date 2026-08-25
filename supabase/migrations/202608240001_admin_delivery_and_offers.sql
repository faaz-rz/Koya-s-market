-- Give MFA-authenticated staff explicit control over delivery pricing and
-- start the catalogue without imported offers. Future offers are created only
-- through the validated, audited admin_save_product RPC.

update public.products
set discount_price_paise = null
where discount_price_paise is not null;

create or replace function public.admin_update_delivery_pricing(
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
  set delivery_charge_paise = requested_delivery_charge_paise,
      free_delivery_threshold_paise = requested_free_delivery_threshold_paise,
      updated_at = now()
  where id = 1
  returning * into updated;

  insert into public.admin_audit_logs (
    admin_id, action, entity_type, entity_id, before_data, after_data
  ) values (
    auth.uid(), 'update_delivery_pricing', 'store_settings', '1',
    to_jsonb(previous), to_jsonb(updated)
  );
end;
$$;

revoke all on function public.admin_update_delivery_pricing(integer, integer)
from public, anon, authenticated;
grant execute on function public.admin_update_delivery_pricing(integer, integer)
to authenticated;
