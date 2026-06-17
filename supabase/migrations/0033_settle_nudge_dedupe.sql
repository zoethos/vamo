-- S46 gate fix — settle nudges must be single-shot per (user, trip).
--
-- The lifecycle RPC stamps trip_members.settle_nudged_at once, but the edge
-- function fans out to everyone stamped in the last 24h, so two runs inside
-- that window (manual dry-run + cron, or a cron retry) inserted duplicate
-- settle-nudge notifications. Enforce uniqueness in the table and make
-- record_notification return null instead of raising on the duplicate —
-- the edge function already treats null as "recorded previously, don't count".
--
-- Note: the index was applied to production manually on 2026-06-11 during the
-- S46 gate dry-run; `if not exists` makes this re-apply cleanly.

create unique index if not exists idx_notifications_settle_nudge_once
  on public.notifications (user_id, trip_id, type)
  where type = 'settle_nudge';

create or replace function record_notification(
  p_user_id uuid,
  p_trip_id uuid,
  p_type text,
  p_title text,
  p_body text,
  p_route text
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
begin
  insert into notifications (user_id, trip_id, type, title, body, route)
  values (p_user_id, p_trip_id, p_type, p_title, p_body, p_route)
  on conflict do nothing
  returning id into v_id;
  return v_id;  -- null when the partial unique index suppressed a duplicate
end;
$$;

revoke all on function record_notification(uuid, uuid, text, text, text, text) from public;
grant execute on function record_notification(uuid, uuid, text, text, text, text)
  to service_role;
