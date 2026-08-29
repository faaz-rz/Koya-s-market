-- Google Play-compliant customer account deletion. Transaction rows are kept
-- only as anonymized business records; authentication, profile, address,
-- notification, and offer-redemption data is removed with the Auth user.

alter table public.orders
  drop constraint if exists orders_user_id_fkey;

alter table public.orders
  alter column user_id drop not null;

alter table public.orders
  add constraint orders_user_id_fkey
  foreign key (user_id) references auth.users(id) on delete set null;

create or replace function public.protect_and_anonymize_deleted_customer()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Staff identities and audit history are managed through the admin access
  -- process, never through the customer application's self-service control.
  if exists (
    select 1 from public.admins where user_id = old.id
  ) then
    raise exception 'Staff accounts must be removed by an authorized administrator';
  end if;

  -- Removing contact details during an active pickup or delivery would make
  -- fulfilment unsafe. The customer can delete after completion/cancellation,
  -- while the public request route remains available for assisted handling.
  if exists (
    select 1
    from public.orders
    where user_id = old.id
      and order_status not in ('collected', 'delivered', 'cancelled', 'rejected')
  ) then
    raise exception 'Complete or cancel active orders before deleting this account';
  end if;

  update public.orders
  set address_id = null,
      delivery_address_text = case
        when fulfilment_type = 'delivery' then 'Removed after account deletion'
        else null
      end,
      delivery_instructions = '',
      customer_name_snapshot = 'Deleted customer',
      customer_phone_snapshot = '',
      delivery_recipient_name_snapshot = null,
      delivery_recipient_phone_snapshot = null
  where user_id = old.id;

  return old;
end;
$$;

drop trigger if exists protect_and_anonymize_deleted_customer
on auth.users;
create trigger protect_and_anonymize_deleted_customer
before delete on auth.users
for each row execute function public.protect_and_anonymize_deleted_customer();

revoke all on function public.protect_and_anonymize_deleted_customer()
from public, anon, authenticated;

comment on function public.protect_and_anonymize_deleted_customer() is
  'Blocks unsafe active-order deletion and removes customer PII from retained transaction records.';
