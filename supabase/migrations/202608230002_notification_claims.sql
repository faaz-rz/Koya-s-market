-- Prevent two notification workers from sending the same queued message at
-- the same time. Stale claims become available again after five minutes.

alter table public.notification_queue
add column if not exists locked_at timestamptz;

create index if not exists notification_queue_pending_idx
on public.notification_queue (created_at)
where processed_at is null and attempts < 5;

create or replace function public.claim_notification_batch(
  requested_limit integer default 50
) returns table (
  id uuid,
  user_id uuid,
  title text,
  body text,
  data jsonb,
  attempts integer
)
language sql
security invoker
set search_path = ''
as $$
  with candidates as (
    select queue.id
    from public.notification_queue as queue
    where queue.processed_at is null
      and queue.attempts < 5
      and (
        queue.locked_at is null or
        queue.locked_at < now() - interval '5 minutes'
      )
    order by queue.created_at
    for update skip locked
    limit least(greatest(coalesce(requested_limit, 50), 1), 100)
  )
  update public.notification_queue as queue
  set locked_at = now()
  from candidates
  where queue.id = candidates.id
  returning queue.id, queue.user_id, queue.title, queue.body,
            queue.data, queue.attempts;
$$;

revoke all on function public.claim_notification_batch(integer)
from public, anon, authenticated;
grant execute on function public.claim_notification_batch(integer)
to service_role;
