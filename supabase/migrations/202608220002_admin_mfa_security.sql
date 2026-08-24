-- Require a verified second factor for every privileged admin policy and RPC.
-- The admins_self_read policy intentionally remains available at AAL1 so an
-- approved staff member can confirm membership before enrolling their factor.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2'
    and exists (
      select 1
      from public.admins
      where user_id = auth.uid()
        and active = true
    );
$$;

revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to anon, authenticated;

comment on function public.is_admin() is
  'True only for active staff whose current Supabase session has MFA assurance level AAL2.';
