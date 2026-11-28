-- A password session alone cannot read staff data or perform staff actions.
-- GoTrue records email code verification as 'otp' in the signed AMR claim.
-- Keep SMS and anonymous authentication disabled for this project.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null
    and coalesce((auth.jwt()->'amr') @> '[{"method":"otp"}]'::jsonb, false)
    and coalesce(auth.jwt()->>'phone', '') = ''
    and exists (
      select 1 from public.admins where user_id = auth.uid() and active
    );
$$;

revoke all on function public.is_admin() from public, anon;
grant execute on function public.is_admin() to authenticated, service_role;

comment on function public.is_admin() is
  'Requires an active staff membership and a session established by verification code.';
