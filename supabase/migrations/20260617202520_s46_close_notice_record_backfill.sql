-- S46 gate fix: a closing-banner view must not stamp the deemed-close clock
-- without also creating the durable close_notice notification row.
--
-- Before this migration, `stamp_close_notice_viewed()` only set
-- trip_members.close_notified_at. If a member had the trip open when the owner
-- requested close, realtime showed the closing banner immediately, the banner
-- stamped close_notified_at, and the lifecycle edge job skipped that member
-- because it looked only for `close_notified_at is null`.

-- Close notices are single-shot per user/trip. Deduplicate any existing rows
-- defensively before enforcing that invariant.
with ranked as (
  select
    id,
    row_number() over (
      partition by user_id, trip_id, type
      order by created_at asc, id asc
    ) as rn
  from public.notifications
  where type = 'close_notice'
)
delete from public.notifications n
using ranked r
where n.id = r.id
  and r.rn > 1;

create unique index if not exists idx_notifications_close_notice_once
  on public.notifications (user_id, trip_id, type)
  where type = 'close_notice';

create or replace function stamp_close_notice_viewed(p_trip_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_trip_name text;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  if not is_active_trip_member(p_trip_id, v_uid) then
    raise exception 'not an active member';
  end if;

  select name
  into v_trip_name
  from trips
  where id = p_trip_id
    and lifecycle = 'closing';

  if v_trip_name is null then
    raise exception 'trip is not closing';
  end if;

  perform record_notification(
    v_uid,
    p_trip_id,
    'close_notice',
    'Trip is closing',
    coalesce(v_trip_name, 'your trip') ||
      ' — review balances. Auto-closes 14 days after you''re notified.',
    '/trips/' || p_trip_id::text || '/close-report'
  );

  perform _stamp_member_close_notified(p_trip_id, v_uid);
end;
$$;

revoke all on function stamp_close_notice_viewed(uuid) from public;
grant execute on function stamp_close_notice_viewed(uuid) to authenticated;

-- Repair members already stamped by the old banner fallback but missing the
-- durable inbox row. Preserve the original notice timestamp for ordering.
insert into public.notifications (
  user_id,
  trip_id,
  type,
  title,
  body,
  route,
  created_at
)
select
  m.user_id,
  m.trip_id,
  'close_notice',
  'Trip is closing',
  coalesce(t.name, 'your trip') ||
    ' — review balances. Auto-closes 14 days after you''re notified.',
  '/trips/' || m.trip_id::text || '/close-report',
  coalesce(m.close_notified_at, now())
from public.trip_members m
join public.trips t on t.id = m.trip_id
where m.status = 'active'
  and t.lifecycle = 'closing'
  and m.close_notified_at is not null
  and not exists (
    select 1
    from public.notifications n
    where n.user_id = m.user_id
      and n.trip_id = m.trip_id
      and n.type = 'close_notice'
)
on conflict do nothing;

-- Repair the inverse partial-failure case too: a durable close_notice row
-- exists, but the lifecycle clock was never stamped after the record.
with first_close_notice as (
  select
    user_id,
    trip_id,
    min(created_at) as created_at
  from public.notifications
  where type = 'close_notice'
  group by user_id, trip_id
)
update public.trip_members m
set close_notified_at = f.created_at
from first_close_notice f
join public.trips t on t.id = f.trip_id
where m.user_id = f.user_id
  and m.trip_id = f.trip_id
  and m.status = 'active'
  and t.lifecycle = 'closing'
  and m.close_notified_at is null;
