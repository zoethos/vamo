-- Editable trip dates (owner-only) with phase rules.
-- Contract:
--   * only on ACTIVE trips (no edits once closing/closed/cancelled/unresolved)
--   * not started (start_date null or in the future): both dates may move
--   * started   (start_date today or past): start is LOCKED, end may move
-- Mirrors the owner-only, state-guarded RPC pattern in 0015_trip_lifecycle.sql.

create or replace function update_trip_dates(
  p_trip_id    uuid,
  p_start_date date default null,
  p_end_date   date default null
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_old_start date;
  v_started   boolean;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  if not is_trip_owner(p_trip_id) then
    raise exception 'only owner may edit trip dates';
  end if;

  select start_date into v_old_start
  from trips
  where id = p_trip_id and lifecycle = 'active';
  if not found then
    raise exception 'trip dates can only be edited on an active trip';
  end if;

  v_started := v_old_start is not null and v_old_start <= current_date;

  -- A started trip's start date already happened; it cannot be moved.
  -- (Passing the same value back is a no-op and allowed.)
  if v_started and p_start_date is distinct from v_old_start then
    raise exception 'start date is locked once the trip has started';
  end if;

  if p_start_date is not null and p_end_date is not null
     and p_end_date < p_start_date then
    raise exception 'end date cannot be before start date';
  end if;

  update trips
  set start_date = p_start_date,
      end_date   = p_end_date
  where id = p_trip_id;
end;
$$;

revoke all on function update_trip_dates(uuid, date, date) from public;
grant execute on function update_trip_dates(uuid, date, date) to authenticated;
