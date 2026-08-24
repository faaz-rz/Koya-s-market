-- Reduce privileged browser access to narrowly validated, audited operations.

-- Product writes used to rely on a broad ALL policy. Route them through one
-- security-definer RPC so a modified browser client cannot bypass validation
-- or the audit trail.
drop policy if exists products_admin_write on public.products;

-- The current dashboard does not manage these resources. Keep their public or
-- authenticated read policies, but remove unused direct mutation privileges
-- until each write path has its own validated and audited RPC.
drop policy if exists categories_admin_write on public.categories;
drop policy if exists banners_admin_write on public.banners;
drop policy if exists settings_admin_write on public.store_settings;
drop policy if exists pincodes_admin_write on public.serviceable_pincodes;
drop policy if exists slots_admin_write on public.fulfilment_slots;

-- Orders contain the delivery snapshot that staff need to fulfil an order.
-- They do not need broad access to edit a customer's saved address book or to
-- read every profile and queued notification.
drop policy if exists profiles_own_read on public.profiles;
create policy profiles_own_read on public.profiles for select
using (id = auth.uid());

drop policy if exists addresses_own_all on public.addresses;
create policy addresses_own_all on public.addresses for all
using (user_id = auth.uid())
with check (user_id = auth.uid());

drop policy if exists notification_own_read on public.notification_queue;
create policy notification_own_read on public.notification_queue for select
using (user_id = auth.uid());

create or replace function public.admin_save_product(
  target_product_id uuid,
  product_category_id uuid,
  product_name text,
  product_description text,
  product_unit text,
  product_price_paise integer,
  product_discount_price_paise integer,
  product_stock_quantity integer,
  product_featured boolean,
  product_subcategory text,
  product_brand text,
  product_image_path text default null
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  previous public.products%rowtype;
  saved_id uuid;
  before_snapshot jsonb;
  after_snapshot jsonb;
  clean_name text := btrim(coalesce(product_name, ''));
  clean_description text := btrim(coalesce(product_description, ''));
  clean_unit text := btrim(coalesce(product_unit, ''));
  clean_subcategory text := btrim(coalesce(product_subcategory, ''));
  clean_brand text := btrim(coalesce(product_brand, ''));
begin
  if not public.is_admin() then raise exception 'Admin access required'; end if;

  if product_category_id is null or not exists (
    select 1 from public.categories
    where id = product_category_id and active
  ) then raise exception 'Choose an active category'; end if;

  if length(clean_name) < 2 or length(clean_name) > 200 then
    raise exception 'Product name must be between 2 and 200 characters';
  end if;
  if length(clean_description) < 2 or length(clean_description) > 2000 then
    raise exception 'Description must be between 2 and 2000 characters';
  end if;
  if length(clean_unit) < 1 or length(clean_unit) > 80 then
    raise exception 'Unit must be between 1 and 80 characters';
  end if;
  if length(clean_subcategory) > 120 or length(clean_brand) > 120 then
    raise exception 'Brand and subcategory must be 120 characters or fewer';
  end if;
  if product_price_paise is null or
     product_price_paise < 1 or product_price_paise > 100000000 then
    raise exception 'Price is outside the allowed range';
  end if;
  if product_discount_price_paise is not null and (
    product_discount_price_paise < 1 or
    product_discount_price_paise >= product_price_paise
  ) then raise exception 'Offer price must be lower than the regular price'; end if;
  if product_stock_quantity is null or
     product_stock_quantity < 0 or product_stock_quantity > 999999 then
    raise exception 'Stock must be between 0 and 999999';
  end if;

  if product_image_path is not null then
    if product_image_path !~ (
      '^products/' || auth.uid()::text || '/[0-9]+\.(jpg|png|webp)$'
    ) then raise exception 'Invalid product image path'; end if;
    if not exists (
      select 1 from storage.objects
      where bucket_id = 'product-images'
        and name = product_image_path
        and owner_id = auth.uid()::text
    ) then raise exception 'Product image was not uploaded by this admin'; end if;
  end if;

  if target_product_id is null then
    insert into public.products (
      category_id, name, description, unit, price_paise,
      discount_price_paise, stock_quantity, active, featured, subcategory,
      brand, image_path
    ) values (
      product_category_id, clean_name, clean_description, clean_unit,
      product_price_paise, product_discount_price_paise,
      product_stock_quantity, true, coalesce(product_featured, false),
      clean_subcategory, clean_brand, product_image_path
    ) returning id into saved_id;
  else
    select * into previous
    from public.products
    where id = target_product_id
    for update;
    if previous.id is null then raise exception 'Product not found'; end if;

    before_snapshot := jsonb_build_object(
      'category_id', previous.category_id,
      'name', previous.name,
      'description', previous.description,
      'unit', previous.unit,
      'price_paise', previous.price_paise,
      'discount_price_paise', previous.discount_price_paise,
      'stock_quantity', previous.stock_quantity,
      'active', previous.active,
      'featured', previous.featured,
      'subcategory', previous.subcategory,
      'brand', previous.brand,
      'image_path', previous.image_path
    );

    update public.products
    set category_id = product_category_id,
        name = clean_name,
        description = clean_description,
        unit = clean_unit,
        price_paise = product_price_paise,
        discount_price_paise = product_discount_price_paise,
        stock_quantity = product_stock_quantity,
        active = true,
        featured = coalesce(product_featured, false),
        subcategory = clean_subcategory,
        brand = clean_brand,
        image_path = coalesce(product_image_path, image_path),
        external_image_url = case
          when product_image_path is null then external_image_url else null
        end,
        image_attribution = case
          when product_image_path is null then image_attribution else null
        end,
        image_source_url = case
          when product_image_path is null then image_source_url else null
        end
    where id = target_product_id
    returning id into saved_id;
  end if;

  select jsonb_build_object(
    'category_id', category_id,
    'name', name,
    'description', description,
    'unit', unit,
    'price_paise', price_paise,
    'discount_price_paise', discount_price_paise,
    'stock_quantity', stock_quantity,
    'active', active,
    'featured', featured,
    'subcategory', subcategory,
    'brand', brand,
    'image_path', image_path
  ) into after_snapshot
  from public.products
  where id = saved_id;

  insert into public.admin_audit_logs (
    admin_id, action, entity_type, entity_id, before_data, after_data
  ) values (
    auth.uid(),
    case when target_product_id is null then 'create_product' else 'update_product' end,
    'product', saved_id::text, before_snapshot, after_snapshot
  );

  return saved_id;
end;
$$;

-- Product image uploads are unique paths. Admins may only create and clean up
-- objects owned by their own authenticated account; service-role bulk imports
-- continue to bypass these browser policies.
drop policy if exists product_images_admin_insert on storage.objects;
drop policy if exists product_images_admin_update on storage.objects;
drop policy if exists product_images_admin_delete on storage.objects;

create policy product_images_admin_insert
on storage.objects for insert to authenticated
with check (
  bucket_id = 'product-images'
  and public.is_admin()
  and (storage.foldername(name))[1] = 'products'
  and (storage.foldername(name))[2] = auth.uid()::text
  and owner_id = auth.uid()::text
);

create policy product_images_admin_delete
on storage.objects for delete to authenticated
using (
  bucket_id = 'product-images'
  and public.is_admin()
  and owner_id = auth.uid()::text
);

-- Supabase recommends an empty search_path for every security-definer
-- function. All referenced relations in these functions are schema-qualified.
alter function public.is_admin() set search_path = '';
alter function public.handle_new_user() set search_path = '';
alter function public.place_order(
  jsonb, public.fulfilment_type, uuid, date, uuid,
  public.payment_method, text, text
) set search_path = '';
alter function public.cancel_own_order(uuid, text) set search_path = '';
alter function public.update_order_status(
  uuid, public.order_status, timestamptz, text, text
) set search_path = '';
alter function public.queue_status_notification() set search_path = '';
alter function public.admin_set_product_stock(uuid, integer) set search_path = '';
alter function public.admin_adjust_product_stock(uuid, integer) set search_path = '';

-- Functions are executable by PUBLIC unless explicitly revoked. Start from a
-- deny-by-default posture and grant only the RPCs used by browser clients.
revoke execute on all functions in schema public from public, anon, authenticated;
alter default privileges in schema public revoke execute on functions from public;

grant execute on function public.is_admin() to anon, authenticated;
grant execute on function public.place_order(
  jsonb, public.fulfilment_type, uuid, date, uuid,
  public.payment_method, text, text
) to authenticated;
grant execute on function public.cancel_own_order(uuid, text) to authenticated;
grant execute on function public.update_order_status(
  uuid, public.order_status, timestamptz, text, text
) to authenticated;
grant execute on function public.admin_set_product_stock(uuid, integer)
to authenticated;
grant execute on function public.admin_adjust_product_stock(uuid, integer)
to authenticated;
grant execute on function public.admin_save_product(
  uuid, uuid, text, text, text, integer, integer, integer,
  boolean, text, text, text
) to authenticated;
