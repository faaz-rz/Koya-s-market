-- Every subscribed table must be published. Missing store_settings could leave
-- a joined channel with a replication error and silently force polling.
-- Existing authenticated RLS still controls which rows reach each subscriber.
do $$
declare
  live_table text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach live_table in array array['products', 'orders', 'offers', 'store_settings']
    loop
      if not exists (
        select 1 from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public' and tablename = live_table
      ) then
        execute format('alter publication supabase_realtime add table public.%I', live_table);
      end if;
    end loop;
  end if;
end;
$$;
