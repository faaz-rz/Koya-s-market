-- Push activation is explicit. No outbound traffic occurs until credentials
-- and physical-device verification are ready. Secrets never enter app clients.
create table koyas_private.push_dispatch_config (
  id boolean primary key default true check(id), enabled boolean not null default false,
  endpoint text, secret_id uuid, secret_digest text
);
alter table koyas_private.push_dispatch_config enable row level security;
revoke all on koyas_private.push_dispatch_config from public,anon,authenticated;
insert into koyas_private.push_dispatch_config(id) values(true);

alter table public.device_tokens add column sound_enabled boolean not null default true;
create function public.register_push_device(requested_token text, requested_platform text, requested_sound_enabled boolean)
returns boolean language plpgsql security definer set search_path='' as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  perform public.register_device_token(requested_token, requested_platform);
  update public.device_tokens set sound_enabled=coalesce(requested_sound_enabled,true)
    where user_id=auth.uid() and token=requested_token;
  return coalesce((select enabled from koyas_private.push_dispatch_config where id),false);
end;
$$;
revoke all on function public.register_push_device(text,text,boolean) from public,anon,authenticated;
grant execute on function public.register_push_device(text,text,boolean) to authenticated;

alter table public.notification_queue add column claim_token uuid,
  add column delivered_device_ids uuid[] not null default '{}',
  add column next_attempt_at timestamptz not null default now(),
  add column last_error_code text;

drop function public.claim_notification_batch(integer);
create function public.claim_notification_batch(requested_limit integer default 20)
returns table(id uuid,user_id uuid,title text,body text,data jsonb,attempts integer,
  claim_token uuid,delivered_device_ids uuid[])
language plpgsql security invoker set search_path='' as $$
begin
  -- Old readiness/delivery messages must not arrive after completion/cancellation.
  update public.notification_queue q set processed_at=now(),last_error_code='obsolete'
  where q.processed_at is null and (q.created_at < now()-interval '24 hours'
    or not exists(select 1 from public.orders o where o.id=q.order_id and o.user_id=q.user_id
      and o.order_status::text=q.data->>'status'));
  return query with candidates as (
    select q.id from public.notification_queue q
    where q.processed_at is null and q.attempts<5 and q.next_attempt_at<=now()
      and (q.locked_at is null or q.locked_at<now()-interval '5 minutes')
    order by q.created_at for update skip locked
    limit least(greatest(coalesce(requested_limit,20),1),50)
  ) update public.notification_queue q set locked_at=now(),claim_token=gen_random_uuid(),attempts=q.attempts+1
    from candidates c where q.id=c.id
    returning q.id,q.user_id,q.title,q.body,q.data,q.attempts,q.claim_token,q.delivered_device_ids;
end;
$$;
revoke all on function public.claim_notification_batch(integer) from public,anon,authenticated;
grant execute on function public.claim_notification_batch(integer) to service_role;

create function public.acknowledge_notification_device(requested_id uuid,requested_claim uuid,requested_device uuid)
returns boolean language plpgsql security invoker set search_path='' as $$
begin
  update public.notification_queue q
    set delivered_device_ids=case when requested_device=any(q.delivered_device_ids) then q.delivered_device_ids
      else array_append(q.delivered_device_ids,requested_device) end
    where q.id=requested_id and q.claim_token=requested_claim and q.processed_at is null
      and q.locked_at>now()-interval '5 minutes';
  return found;
end;
$$;
create function public.finish_notification_dispatch(requested_id uuid,requested_claim uuid,successful boolean,error_code text default null)
returns boolean language plpgsql security invoker set search_path='' as $$
begin
  update public.notification_queue q set
    processed_at=case when successful then now() else null end,
    next_attempt_at=now()+make_interval(secs=>least(600,15*power(2,least(q.attempts,5))::integer)),
    locked_at=null, claim_token=null,last_error_code=left(error_code,60)
  where q.id=requested_id and q.claim_token=requested_claim and q.processed_at is null
    and q.locked_at>now()-interval '5 minutes';
  return found;
end;
$$;
revoke all on function public.acknowledge_notification_device(uuid,uuid,uuid) from public,anon,authenticated;
revoke all on function public.finish_notification_dispatch(uuid,uuid,boolean,text) from public,anon,authenticated;
grant execute on function public.acknowledge_notification_device(uuid,uuid,uuid) to service_role;
grant execute on function public.finish_notification_dispatch(uuid,uuid,boolean,text) to service_role;

create function public.authorize_push_dispatch(requested_secret text)
returns boolean language sql security definer set search_path='' as $$
  select coalesce((select enabled and length(requested_secret) between 32 and 256
    and secret_digest=encode(sha256(convert_to(requested_secret,'UTF8')),'hex')
    from koyas_private.push_dispatch_config where id),false);
$$;
revoke all on function public.authorize_push_dispatch(text) from public,anon,authenticated;
grant execute on function public.authorize_push_dispatch(text) to service_role;
notify pgrst,'reload schema';
