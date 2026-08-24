-- Safe starter catalogue and store configuration. Admins can edit everything later.
insert into public.categories (id, name, sort_order) values
  ('10000000-0000-4000-8000-000000000001', 'Fruits & Vegetables', 1),
  ('10000000-0000-4000-8000-000000000002', 'Dairy & Eggs', 2),
  ('10000000-0000-4000-8000-000000000003', 'Staples', 3),
  ('10000000-0000-4000-8000-000000000004', 'Snacks & Drinks', 4),
  ('10000000-0000-4000-8000-000000000005', 'Household', 5)
on conflict (id) do nothing;

insert into public.products (
  id, category_id, name, description, unit, price_paise,
  discount_price_paise, stock_quantity, featured
) values
  ('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001',
   'Fresh Bananas', 'Naturally ripened, hand-selected bananas.', '1 kg', 6800, 6200, 28, true),
  ('20000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001',
   'Farm Tomatoes', 'Juicy red tomatoes for curries and salads.', '1 kg', 5600, null, 18, true),
  ('20000000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000002',
   'Heritage Toned Milk', 'Fresh toned milk for the whole family.', '1 litre', 5800, null, 42, true),
  ('20000000-0000-4000-8000-000000000004', '10000000-0000-4000-8000-000000000002',
   'Farm Fresh Eggs', 'Clean, graded eggs packed safely.', '12 pieces', 9600, 8900, 16, false),
  ('20000000-0000-4000-8000-000000000005', '10000000-0000-4000-8000-000000000003',
   'Aashirvaad Atta', 'Whole wheat flour for soft rotis.', '5 kg pack', 34000, 28900, 22, true),
  ('20000000-0000-4000-8000-000000000006', '10000000-0000-4000-8000-000000000003',
   'Premium Toor Dal', 'Cleaned, unpolished toor dal.', '1 kg pack', 19000, 17500, 14, true),
  ('20000000-0000-4000-8000-000000000007', '10000000-0000-4000-8000-000000000003',
   'Fortune Sunflower Oil', 'Light refined oil for everyday cooking.', '1 litre pouch', 15200, null, 30, false),
  ('20000000-0000-4000-8000-000000000008', '10000000-0000-4000-8000-000000000004',
   'Parle-G Biscuits', 'Classic glucose biscuits for tea-time.', '300 g pack', 3500, null, 55, false),
  ('20000000-0000-4000-8000-000000000009', '10000000-0000-4000-8000-000000000004',
   'Real Mixed Fruit Juice', 'Ready-to-serve family pack.', '1 litre', 11800, 10500, 20, false),
  ('20000000-0000-4000-8000-000000000010', '10000000-0000-4000-8000-000000000005',
   'Surf Excel Easy Wash', 'Detergent powder for machine and hand wash.', '2 kg pack', 27500, null, 12, false)
on conflict (id) do nothing;

insert into public.serviceable_pincodes (pincode) values
  ('500001'), ('500004'), ('500028'), ('500033'), ('500034'), ('500081')
on conflict (pincode) do nothing;

insert into public.fulfilment_slots (
  id, fulfilment_type, label, start_time, end_time, max_orders, sort_order
) values
  ('30000000-0000-4000-8000-000000000001', 'pickup', 'Store hours', '08:00', '21:00', 500, 1),
  ('30000000-0000-4000-8000-000000000005', 'delivery', '10:00 AM – 1:00 PM', '10:00', '13:00', 15, 1),
  ('30000000-0000-4000-8000-000000000006', 'delivery', '2:00 PM – 5:00 PM', '14:00', '17:00', 15, 2),
  ('30000000-0000-4000-8000-000000000007', 'delivery', '6:00 PM – 9:00 PM', '18:00', '21:00', 15, 3)
on conflict (id) do nothing;

insert into public.banners (
  id, title, subtitle, deep_link, sort_order
) values (
  '40000000-0000-4000-8000-000000000001',
  'Free pickup, every day', 'We will notify you when it is ready', '/products', 1
)
on conflict (id) do nothing;
