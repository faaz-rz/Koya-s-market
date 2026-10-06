-- Available on hosted Supabase; portable PostgreSQL tests skip only the hosted
-- extension installation. Dispatch stays disabled until credentials are set.
do $$
declare secret text; created_secret_id uuid;
begin
  if not exists(select 1 from pg_available_extensions where name='pg_net')
    or not exists(select 1 from pg_available_extensions where name='pg_cron')
    or not exists(select 1 from pg_available_extensions where name='supabase_vault') then
    return;
  end if;
  execute 'create extension if not exists pg_net with schema extensions';
  execute 'create extension if not exists pg_cron';
  execute 'create extension if not exists supabase_vault with schema vault';
  secret := gen_random_uuid()::text || gen_random_uuid()::text;
  select vault.create_secret(secret,'koyas_order_push_dispatch','Private database-to-function authorization') into created_secret_id;
  update koyas_private.push_dispatch_config c set secret_id=created_secret_id,
    secret_digest=encode(sha256(convert_to(secret,'UTF8')),'hex') where id;
end;
$$;

create function koyas_private.wake_order_push_dispatch()
returns void language plpgsql security definer set search_path='' as $$
declare config koyas_private.push_dispatch_config%rowtype; secret text;
begin
  select * into config from koyas_private.push_dispatch_config where id;
  if not coalesce(config.enabled,false) or config.endpoint is null or config.secret_id is null then return; end if;
  if not exists(select 1 from public.notification_queue q where q.processed_at is null and q.attempts<5
    and q.next_attempt_at<=now() and (q.locked_at is null or q.locked_at<now()-interval '5 minutes')) then return; end if;
  execute 'select decrypted_secret from vault.decrypted_secrets where id=$1' into secret using config.secret_id;
  perform net.http_post(url:=config.endpoint,headers:=jsonb_build_object('Content-Type','application/json','x-koyas-webhook-secret',secret),
    body:='{}'::jsonb,timeout_milliseconds:=5000);
end;
$$;
revoke all on function koyas_private.wake_order_push_dispatch() from public,anon,authenticated;

create function koyas_private.wake_order_push_trigger()
returns trigger language plpgsql security definer set search_path='' as $$
begin perform koyas_private.wake_order_push_dispatch(); return new; end;
$$;
revoke all on function koyas_private.wake_order_push_trigger() from public,anon,authenticated;
create trigger wake_order_push after insert on public.notification_queue
for each row execute function koyas_private.wake_order_push_trigger();

do $$
begin
  if exists(select 1 from pg_extension where extname='pg_cron') then
    perform cron.schedule('koyas-order-push-retry','* * * * *','select koyas_private.wake_order_push_dispatch();');
  end if;
end;
$$;
