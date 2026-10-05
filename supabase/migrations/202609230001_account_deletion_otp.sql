-- Codes remain in Supabase Auth. One private row per account holds purpose,
-- expiry and limits; it is removed by the Auth-user deletion cascade.
create table public.account_deletion_challenges (
  user_id uuid primary key references auth.users(id) on delete cascade,
  challenge_id uuid not null,
  email text not null,
  status text not null check (status in ('sending','pending','consumed','failed')),
  expires_at timestamptz not null,
  last_sent_at timestamptz not null,
  window_started_at timestamptz not null,
  sends integer not null check (sends between 1 and 8),
  attempts integer not null default 0 check (attempts between 0 and 5)
);
alter table public.account_deletion_challenges enable row level security;
revoke all on public.account_deletion_challenges from public, anon, authenticated, service_role;
grant select, update on public.account_deletion_challenges to service_role;

create function public.begin_account_deletion_otp(target_user uuid, account_email text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare previous public.account_deletion_challenges; stamp timestamptz := clock_timestamp();
  identifier uuid := gen_random_uuid(); count_sends integer := 1; window_start timestamptz := stamp;
begin
  if target_user is null or coalesce(length(account_email),0) not between 3 and 320 then
    return jsonb_build_object('ok',false,'code','invalid_request');
  end if;
  perform pg_advisory_xact_lock(hashtextextended(target_user::text, 230923));
  if exists (select 1 from public.admins where user_id=target_user) then
    return jsonb_build_object('ok',false,'code','staff_account');
  end if;
  if exists (select 1 from public.orders where user_id=target_user
    and order_status not in ('collected','delivered','cancelled','rejected')) then
    return jsonb_build_object('ok',false,'code','active_orders');
  end if;
  select * into previous from public.account_deletion_challenges where user_id=target_user for update;
  if found then
    if previous.status='consumed' and previous.expires_at>stamp then
      return jsonb_build_object('ok',false,'code','deletion_in_progress','retry_after',60);
    end if;
    if previous.last_sent_at>stamp-interval '60 seconds' then
      return jsonb_build_object('ok',false,'code','rate_limited',
        'retry_after',ceil(extract(epoch from previous.last_sent_at+interval '60 seconds'-stamp))::integer);
    end if;
    if previous.window_started_at>stamp-interval '1 hour' then
      if previous.sends>=8 then
        return jsonb_build_object('ok',false,'code','rate_limited',
          'retry_after',ceil(extract(epoch from previous.window_started_at+interval '1 hour'-stamp))::integer);
      end if;
      count_sends:=previous.sends+1; window_start:=previous.window_started_at;
    end if;
  end if;
  insert into public.account_deletion_challenges
    (user_id,challenge_id,email,status,expires_at,last_sent_at,window_started_at,sends,attempts)
  values (target_user,identifier,lower(trim(account_email)),'sending',stamp+interval '10 minutes',stamp,window_start,count_sends,0)
  on conflict (user_id) do update set challenge_id=excluded.challenge_id,email=excluded.email,
    status=excluded.status,expires_at=excluded.expires_at,last_sent_at=excluded.last_sent_at,
    window_started_at=excluded.window_started_at,sends=excluded.sends,attempts=0;
  return jsonb_build_object('ok',true,'challenge_id',identifier,'expires_at',stamp+interval '10 minutes','retry_after',60);
end;
$$;

create function public.claim_account_deletion_attempt(target_user uuid, requested_challenge uuid, account_email text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare challenge public.account_deletion_challenges;
begin
  select * into challenge from public.account_deletion_challenges where user_id=target_user for update;
  if not found or challenge.challenge_id<>requested_challenge or requested_challenge is null
    or challenge.email is distinct from lower(trim(account_email)) or challenge.status<>'pending'
    or challenge.expires_at<=clock_timestamp() then
    return jsonb_build_object('ok',false,'code','otp_expired');
  end if;
  if challenge.attempts>=5 then return jsonb_build_object('ok',false,'code','attempts_exhausted'); end if;
  update public.account_deletion_challenges set attempts=attempts+1 where user_id=target_user;
  return jsonb_build_object('ok',true);
end;
$$;

create function public.consume_account_deletion_otp(target_user uuid, requested_challenge uuid, account_email text)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  update public.account_deletion_challenges set status='consumed'
  where user_id=target_user and challenge_id=requested_challenge
    and email=lower(trim(account_email)) and status='pending'
    and attempts between 1 and 5 and expires_at>clock_timestamp();
  return found;
end;
$$;
revoke all on function public.begin_account_deletion_otp(uuid,text) from public, anon, authenticated;
revoke all on function public.claim_account_deletion_attempt(uuid,uuid,text) from public, anon, authenticated;
revoke all on function public.consume_account_deletion_otp(uuid,uuid,text) from public, anon, authenticated;
grant execute on function public.begin_account_deletion_otp(uuid,text) to service_role;
grant execute on function public.claim_account_deletion_attempt(uuid,uuid,text) to service_role;
grant execute on function public.consume_account_deletion_otp(uuid,uuid,text) to service_role;

-- Checkout retry fingerprints were added after the original deletion migration
-- and can include personal delivery instructions. Remove those as well.
create or replace function public.protect_and_anonymize_deleted_customer()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  -- Share the customer lock used by place_order_v2. A FK alone prevents an
  -- invalid user ID but does not prevent an active order becoming anonymized.
  perform pg_advisory_xact_lock(hashtextextended(old.id::text, 0));
  if exists (select 1 from public.admins where user_id=old.id) then
    raise exception 'Staff accounts must be removed by an authorized administrator';
  end if;
  if exists (select 1 from public.orders where user_id=old.id
    and order_status not in ('collected','delivered','cancelled','rejected')) then
    raise exception 'Complete or cancel active orders before deleting this account';
  end if;
  update public.orders set address_id=null,
    delivery_address_text=case when fulfilment_type='delivery' then 'Removed after account deletion' else null end,
    delivery_instructions='', customer_name_snapshot='Deleted customer',customer_phone_snapshot='',
    delivery_recipient_name_snapshot=null,delivery_recipient_phone_snapshot=null,
    checkout_request=null
  where user_id=old.id;
  return old;
end;
$$;
revoke all on function public.protect_and_anonymize_deleted_customer() from public,anon,authenticated;
notify pgrst, 'reload schema';
