-- Approved staff use the existing email-verified session. Authenticator
-- assurance is no longer required; membership stays server-owned and active.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null and exists (
    select 1
    from public.admins
    where user_id = auth.uid()
      and active = true
  );
$$;

revoke all on function public.is_admin() from public, anon;
grant execute on function public.is_admin() to authenticated, service_role;

comment on function public.is_admin() is
  'True only for the signed-in user with an active, server-managed staff membership. No authenticator step is required.';
