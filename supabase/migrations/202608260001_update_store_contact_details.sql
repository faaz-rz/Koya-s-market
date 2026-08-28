-- Keep already-initialized environments aligned with the production store
-- contact details. Fresh environments receive the same values from the base
-- schema migration.
update public.store_settings
set
  store_address = '9-1, 43/5, Prashanth Nagar, Langar Houz, Hyderabad, Telangana 500008, India',
  contact_phone = '+91 95029 26383',
  updated_at = now()
where id = 1;
