-- Dashboard owners can preapprove an email without knowing an Auth user UUID.
-- This private, one-time approval is consumed only after Supabase verifies it.
create schema if not exists koyas_private;
revoke all on schema koyas_private from public, anon, authenticated;

create table koyas_private.staff_email_approvals (
  email text primary key check (email = lower(btrim(email)) and email like '%@%'),
  display_name text not null check (length(btrim(display_name)) between 1 and 100),
  approved_at timestamptz not null default now(),
  granted_at timestamptz,
  granted_user_id uuid,
  check ((granted_at is null) = (granted_user_id is null))
);
alter table koyas_private.staff_email_approvals enable row level security;
revoke all on koyas_private.staff_email_approvals from public, anon, authenticated;

create function koyas_private.provision_verified_staff()
returns trigger language plpgsql security definer set search_path = '' as $$
declare approved_name text;
begin
  if new.email is null or new.email_confirmed_at is null then
    return new;
  end if;
  update koyas_private.staff_email_approvals
  set granted_at = now(), granted_user_id = new.id
  where email = lower(btrim(new.email)) and granted_at is null
  returning display_name into approved_name;
  if approved_name is not null then
    insert into public.admins(user_id, display_name, active)
    values (new.id, approved_name, true)
    on conflict (user_id) do nothing;
  end if;
  return new;
end;
$$;
revoke all on function koyas_private.provision_verified_staff() from public, anon, authenticated;

create trigger provision_verified_staff_email
after insert or update of email, email_confirmed_at on auth.users
for each row execute function koyas_private.provision_verified_staff();
