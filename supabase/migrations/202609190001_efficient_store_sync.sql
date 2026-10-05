-- Read-only, content-addressed sync. Hashes and rows are read in ONE SQL
-- snapshot, so late commits, deletes and archiving cannot be missed by a
-- timestamp cursor. Does not change prices, stock or catalogue images.
create function public.sync_bucket(value uuid)
returns integer language sql immutable strict parallel safe set search_path = ''
as $$ select pg_catalog.get_byte(pg_catalog.uuid_send(value), 0) % 64 $$;
revoke all on function public.sync_bucket(uuid) from public, anon, authenticated;

-- Include line edits in the parent order fingerprint as well.
create function public.touch_order_for_item_sync()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op <> 'INSERT' then
    update public.orders set updated_at = clock_timestamp() where id = old.order_id;
  end if;
  if tg_op <> 'DELETE' then
    update public.orders set updated_at = clock_timestamp() where id = new.order_id;
    return new;
  end if;
  return old;
end;
$$;
revoke all on function public.touch_order_for_item_sync() from public, anon, authenticated;
create trigger order_items_sync after insert or update or delete on public.order_items
for each row execute function public.touch_order_for_item_sync();

create function public.sync_store(
  known_catalogue jsonb default '{}',
  known_orders jsonb default '{}',
  known_metadata text default null
) returns jsonb
language plpgsql stable security definer set search_path = '' set statement_timeout = '8s'
as $$
declare customer uuid := auth.uid(); staff boolean := public.is_admin(); result jsonb;
begin
  if customer is null then raise exception 'Authentication required'; end if;
  if known_catalogue is null or jsonb_typeof(known_catalogue) <> 'object'
    or known_orders is null or jsonb_typeof(known_orders) <> 'object' then
    raise exception 'Invalid sync fingerprints';
  end if;
  if octet_length(known_catalogue::text) > 4096 or octet_length(known_orders::text) > 4096
    or length(coalesce(known_metadata, '')) > 32 then
    raise exception 'Sync fingerprints are too large';
  end if;
  if exists (
    select 1 from (select * from jsonb_each_text(known_catalogue) union all select * from jsonb_each_text(known_orders)) e
    where e.key !~ '^([0-9]|[1-5][0-9]|6[0-3])$' or e.value !~ '^[0-9a-f]{32}$'
  ) then raise exception 'Invalid sync fingerprints'; end if;

  with
  buckets as (select generate_series(0,63) as id),
  visible_products as materialized (
    select p.*, public.sync_bucket(p.id) as bucket from public.products p
    join public.categories c on c.id=p.category_id and c.active
    where staff or p.active
  ),
  catalogue_hashes as (
    select b.id, md5(staff::text || ':' || coalesce(string_agg(p.id::text || ':' || p.revision::text, ',' order by p.id),'')) as hash
    from buckets b left join visible_products p on p.bucket=b.id group by b.id
  ),
  catalogue_changes as (
    select h.id, h.hash, coalesce((
      select jsonb_agg(jsonb_build_array(
        p.id,p.category_id,p.name,p.description,p.unit,p.price_paise,p.discount_price_paise,
        p.stock_quantity,p.revision,p.subcategory,p.brand,p.image_path,p.image_attribution,
        p.featured,p.active,p.available,
        case when staff then p.source_product_name end,
        case when staff then p.source_print_name end,
        case when staff then p.source_item_code end,
        case when staff then p.barcode end
      ) order by p.id) from visible_products p where p.bucket=h.id
    ),'[]'::jsonb) as rows
    from catalogue_hashes h where known_catalogue->>h.id::text is distinct from h.hash
  ),
  visible_orders as materialized (
    select o.*, public.sync_bucket(o.id) as bucket from public.orders o
    where staff or o.user_id=customer
  ),
  order_hashes as (
    select b.id, md5(customer::text || ':' || staff::text || ':' || coalesce(string_agg(o.id::text || ':' || o.updated_at::text, ',' order by o.id),'')) as hash
    from buckets b left join visible_orders o on o.bucket=b.id group by b.id
  ),
  order_changes as (
    select h.id,h.hash,coalesce((
      select jsonb_agg((to_jsonb(o)-'bucket'-'checkout_request'-'idempotency_key') ||
        jsonb_build_object('order_items',coalesce((
          select jsonb_agg(jsonb_build_object(
            'product_id',i.product_id,'product_name',i.product_name,'unit',i.unit,
            'unit_price_paise',i.unit_price_paise,'quantity',i.quantity,'is_free_offer_item',i.is_free_offer_item
          ) order by i.id) from public.order_items i where i.order_id=o.id
        ),'[]'::jsonb)) order by o.created_at desc,o.id)
      from visible_orders o where o.bucket=h.id
    ),'[]'::jsonb) as rows
    from order_hashes h where known_orders->>h.id::text is distinct from h.hash
  ),
  metadata as (
    select jsonb_build_object(
      'is_admin',staff,
      'profile',(select jsonb_build_object('full_name',p.full_name,'phone',p.phone) from public.profiles p where p.id=customer),
      'categories',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name) order by c.sort_order,c.id) from public.categories c where c.active),'[]'::jsonb),
      'addresses',coalesce((select jsonb_agg(to_jsonb(a) order by a.is_default desc,a.id) from public.addresses a where a.user_id=customer),'[]'::jsonb),
      'slots',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'label',s.label,'fulfilment_type',s.fulfilment_type) order by s.sort_order,s.id) from public.fulfilment_slots s where s.active),'[]'::jsonb),
      'settings',(select to_jsonb(s) from public.store_settings s where s.id=1),
      'pincodes',coalesce((select jsonb_agg(jsonb_build_object('pincode',p.pincode) order by p.pincode) from public.serviceable_pincodes p where p.active),'[]'::jsonb),
      'offers',coalesce((select jsonb_agg(to_jsonb(o) order by o.created_at desc,o.id) from public.offers o where staff or o.active),'[]'::jsonb)
    ) as data
  )
  select jsonb_build_object(
    'schema',1,'user_id',customer,'is_admin',staff,
    'catalogue',coalesce((select jsonb_agg(to_jsonb(c) order by c.id) from catalogue_changes c),'[]'::jsonb),
    'orders',coalesce((select jsonb_agg(to_jsonb(o) order by o.id) from order_changes o),'[]'::jsonb),
    'metadata_hash',md5(customer::text || metadata.data::text),
    'metadata',case when known_metadata is distinct from md5(customer::text || metadata.data::text) then metadata.data end
  ) into result from metadata;
  return result;
end;
$$;
revoke all on function public.sync_store(jsonb,jsonb,text) from public, anon, authenticated;
grant execute on function public.sync_store(jsonb,jsonb,text) to authenticated;

-- Diagnostic only. Does not delete customer orders or idempotency receipts.
create function public.admin_resource_usage()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_admin() then raise exception 'Admin access required'; end if;
  return jsonb_build_object(
    'database_bytes',pg_database_size(current_database()),
    'public_table_bytes',(select coalesce(sum(pg_total_relation_size(c.oid)),0) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r'),
    'product_count',(select count(*) from public.products),
    'order_count',(select count(*) from public.orders),
    'inventory_receipt_count',(select count(*) from public.admin_inventory_requests),
    'inventory_receipt_bytes',pg_total_relation_size('public.admin_inventory_requests'::regclass),
    'storage_bytes',(select coalesce(sum((metadata->>'size')::bigint),0) from storage.objects where bucket_id='product-images' and metadata->>'size' ~ '^[0-9]+$')
  );
end;
$$;
revoke all on function public.admin_resource_usage() from public, anon, authenticated;
grant execute on function public.admin_resource_usage() to authenticated;
notify pgrst, 'reload schema';
