-- Explicit API grants also work on projects with default table grants disabled.
-- Authenticated clients can read through RLS; writes stay inside checked RPCs.
revoke all on all tables in schema public from public, anon, authenticated;
grant usage on schema public to authenticated;
grant select on public.profiles, public.admins, public.categories, public.products,
  public.addresses, public.store_settings, public.fulfilment_slots,
  public.serviceable_pincodes, public.banners, public.orders, public.order_items,
  public.offers, public.offer_redemptions, public.notification_queue,
  public.admin_audit_logs, public.payment_events to authenticated;
revoke execute on function public.is_admin() from public, anon;

drop policy if exists profiles_own_update on public.profiles;
alter policy profiles_own_read on public.profiles to authenticated
  using (id = (select auth.uid()));
alter policy addresses_own_all on public.addresses to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
alter policy orders_own_read on public.orders to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()));
alter policy order_items_own_read on public.order_items to authenticated
  using ((select public.is_admin()) or exists (
    select 1 from public.orders o
    where o.id = order_items.order_id and o.user_id = (select auth.uid())
  ));
alter policy notification_own_read on public.notification_queue to authenticated
  using (user_id = (select auth.uid()));
alter policy offer_redemptions_own_or_admin_read on public.offer_redemptions to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()));
alter policy products_public_read on public.products to authenticated
  using (active or (select public.is_admin()));
alter policy categories_public_read on public.categories to authenticated
  using (active or (select public.is_admin()));
alter policy banners_public_read on public.banners to authenticated
  using ((select public.is_admin()) or (active and (starts_at is null or starts_at <= now()) and (ends_at is null or ends_at > now())));
alter policy slots_authenticated_read on public.fulfilment_slots to authenticated
  using (active or (select public.is_admin()));
alter policy pincodes_authenticated_read on public.serviceable_pincodes to authenticated
  using (active or (select public.is_admin()));
alter policy offers_customer_or_admin_read on public.offers to authenticated
  using ((select public.is_admin()) or (active and (starts_at is null or starts_at <= now()) and (ends_at is null or ends_at > now())));
alter policy audit_admin_read on public.admin_audit_logs to authenticated
  using ((select public.is_admin()));
alter policy payment_events_admin_read on public.payment_events to authenticated
  using ((select public.is_admin()));

create index admin_audit_logs_admin_idx on public.admin_audit_logs(admin_id);
create index notification_queue_order_idx on public.notification_queue(order_id);
create index notification_queue_user_idx on public.notification_queue(user_id);
create index offer_redemptions_free_product_idx on public.offer_redemptions(free_product_id);
create index offer_redemptions_user_idx on public.offer_redemptions(user_id);
create index offers_free_product_idx on public.offers(free_product_id);
create index order_items_product_idx on public.order_items(product_id);
create index orders_address_idx on public.orders(address_id);
create index orders_applied_offer_idx on public.orders(applied_offer_id);
notify pgrst, 'reload schema';
