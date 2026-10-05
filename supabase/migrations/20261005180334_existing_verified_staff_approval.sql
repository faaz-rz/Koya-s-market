-- Approving a person who already verified a customer account must also work;
-- a returning OTP login need not change their email_confirmed_at field.
create function koyas_private.provision_existing_verified_staff()
returns trigger language plpgsql security definer set search_path = '' as $$
declare verified_user uuid; approved_name text;
begin
  if new.granted_at is not null then return new; end if;
  select u.id into verified_user from auth.users u
  where lower(btrim(u.email)) = new.email and u.email_confirmed_at is not null
  limit 1;
  if verified_user is null then return new; end if;
  update koyas_private.staff_email_approvals
  set granted_at = now(), granted_user_id = verified_user
  where email = new.email and granted_at is null
  returning display_name into approved_name;
  if approved_name is not null then
    insert into public.admins(user_id, display_name, active)
    values (verified_user, approved_name, true)
    on conflict (user_id) do nothing;
  end if;
  return new;
end;
$$;
revoke all on function koyas_private.provision_existing_verified_staff() from public, anon, authenticated;
create trigger provision_existing_verified_staff_email
after insert on koyas_private.staff_email_approvals
for each row execute function koyas_private.provision_existing_verified_staff();
