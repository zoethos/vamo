-- Atomic trip creation: inserts trips + owner membership in one transaction.
-- Mirrors join_trip() — avoids orphaned trips when membership insert fails.

create or replace function create_trip(
  p_id            uuid,
  p_name          text,
  p_destination   text default null,
  p_start_date    date default null,
  p_end_date      date default null,
  p_base_currency char(3) default 'EUR'
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  if p_name is null or trim(p_name) = '' then
    raise exception 'name required';
  end if;

  insert into trips (
    id, name, destination, start_date, end_date, owner_id, base_currency
  ) values (
    p_id,
    trim(p_name),
    nullif(trim(p_destination), ''),
    p_start_date,
    p_end_date,
    v_uid,
    p_base_currency
  );

  insert into trip_members (trip_id, user_id, role, status)
  values (p_id, v_uid, 'owner', 'active');

  return p_id;
end;
$$;

revoke all on function create_trip(uuid, text, text, date, date, char) from public;
grant execute on function create_trip(uuid, text, text, date, date, char) to authenticated;
