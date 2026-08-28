-- Full catalogue control for the staff app. Product deletion is deliberately
-- implemented as reversible archiving so historical order lines remain valid.

create or replace function public.admin_save_product_v2(
  target_product_id uuid,
  product_category_id uuid,
  product_name text,
  product_description text,
  product_unit text,
  product_price_paise integer,
  product_discount_price_paise integer,
  product_stock_quantity integer,
  product_featured boolean,
  product_active boolean,
  product_available boolean,
  product_subcategory text,
  product_brand text,
  product_billing_name text,
  product_print_name text,
  product_item_code text,
  product_barcode text,
  product_image_path text default null,
  remove_product_image boolean default false
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
  audit_action text;
  clean_name text := btrim(coalesce(product_name, ''));
  clean_description text := btrim(coalesce(product_description, ''));
  clean_unit text := btrim(coalesce(product_unit, ''));
  clean_subcategory text := btrim(coalesce(product_subcategory, ''));
  clean_brand text := btrim(coalesce(product_brand, ''));
  clean_billing_name text := btrim(coalesce(product_billing_name, ''));
  clean_print_name text := btrim(coalesce(product_print_name, ''));
  clean_item_code text := btrim(coalesce(product_item_code, ''));
  clean_barcode text := btrim(coalesce(product_barcode, ''));
  clean_active boolean := coalesce(product_active, true);
  clean_available boolean :=
    coalesce(product_active, true) and coalesce(product_available, true);
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
  if length(clean_billing_name) > 200 or length(clean_print_name) > 200 then
    raise exception 'Billing and print names must be 200 characters or fewer';
  end if;
  if length(clean_item_code) > 80 or length(clean_barcode) > 80 then
    raise exception 'SKU and barcode must be 80 characters or fewer';
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
  if coalesce(remove_product_image, false) and product_image_path is not null then
    raise exception 'Choose either a replacement image or image removal';
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
      discount_price_paise, stock_quantity, active, available, featured,
      subcategory, brand, source_product_name, source_print_name,
      source_item_code, barcode, image_path
    ) values (
      product_category_id, clean_name, clean_description, clean_unit,
      product_price_paise, product_discount_price_paise,
      product_stock_quantity, clean_active, clean_available,
      coalesce(product_featured, false), clean_subcategory, clean_brand,
      coalesce(nullif(clean_billing_name, ''), clean_name),
      coalesce(nullif(clean_print_name, ''), clean_name),
      nullif(clean_item_code, ''), nullif(clean_barcode, ''),
      product_image_path
    ) returning id into saved_id;
    audit_action := 'create_product';
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
      'available', previous.available,
      'featured', previous.featured,
      'subcategory', previous.subcategory,
      'brand', previous.brand,
      'billing_name', previous.source_product_name,
      'print_name', previous.source_print_name,
      'item_code', previous.source_item_code,
      'barcode', previous.barcode,
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
        active = clean_active,
        available = clean_available,
        featured = coalesce(product_featured, false),
        subcategory = clean_subcategory,
        brand = clean_brand,
        source_product_name = coalesce(nullif(clean_billing_name, ''), clean_name),
        source_print_name = coalesce(nullif(clean_print_name, ''), clean_name),
        source_item_code = nullif(clean_item_code, ''),
        barcode = nullif(clean_barcode, ''),
        image_path = case
          when coalesce(remove_product_image, false) then null
          when product_image_path is not null then product_image_path
          else image_path
        end,
        external_image_url = case
          when coalesce(remove_product_image, false) or product_image_path is not null
          then null else external_image_url
        end,
        image_attribution = case
          when coalesce(remove_product_image, false) or product_image_path is not null
          then null else image_attribution
        end,
        image_source_url = case
          when coalesce(remove_product_image, false) or product_image_path is not null
          then null else image_source_url
        end
    where id = target_product_id
    returning id into saved_id;

    audit_action := case
      when previous.active and not clean_active then 'archive_product'
      when not previous.active and clean_active then 'restore_product'
      else 'update_product'
    end;
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
    'available', available,
    'featured', featured,
    'subcategory', subcategory,
    'brand', brand,
    'billing_name', source_product_name,
    'print_name', source_print_name,
    'item_code', source_item_code,
    'barcode', barcode,
    'image_path', image_path
  ) into after_snapshot
  from public.products
  where id = saved_id;

  insert into public.admin_audit_logs (
    admin_id, action, entity_type, entity_id, before_data, after_data
  ) values (
    auth.uid(), audit_action, 'product', saved_id::text,
    before_snapshot, after_snapshot
  );

  return saved_id;
end;
$$;

revoke all on function public.admin_save_product_v2(
  uuid, uuid, text, text, text, integer, integer, integer,
  boolean, boolean, boolean, text, text, text, text, text, text, text, boolean
) from public, anon, authenticated;

grant execute on function public.admin_save_product_v2(
  uuid, uuid, text, text, text, integer, integer, integer,
  boolean, boolean, boolean, text, text, text, text, text, text, text, boolean
) to authenticated;

notify pgrst, 'reload schema';
