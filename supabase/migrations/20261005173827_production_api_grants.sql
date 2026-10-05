-- New hosted projects can disable automatic table grants to the Data API.
-- Staff login reads only the caller's allowlist record before asking for MFA.
-- All customer/store writes continue through their restricted, audited RPCs.
grant usage on schema public to authenticated;
revoke all on table public.admins from public, anon;
revoke insert, update, delete, truncate, references, trigger
  on table public.admins from authenticated;
grant select on table public.admins to authenticated;

alter table public.admins enable row level security;
drop policy if exists admins_self_read on public.admins;
create policy admins_self_read on public.admins
  for select to authenticated
  using (user_id = (select auth.uid()));
