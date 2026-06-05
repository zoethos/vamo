-- S16 / R1 — trip member roles: owner | co-admin | member
-- co-admin: edit trip content (same RLS as owner today); NOT role grants,
-- trip delete/cancel/close (guarded when those columns land in S17).

alter type member_role add value if not exists 'co-admin';

-- ---------- role helpers (security definer — safe under RLS) ----------
create or replace function is_trip_owner(p_trip uuid) returns boolean
language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from trips t
    where t.id = p_trip and t.owner_id = auth.uid()
  );
$$;

create or replace function is_trip_co_admin(p_trip uuid) returns boolean
language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from trip_members m
    where m.trip_id = p_trip
      and m.user_id = auth.uid()
      and m.status = 'active'
      and m.role = 'co-admin'::member_role
  );
$$;

create or replace function can_edit_trip_content(p_trip uuid) returns boolean
language sql security definer stable set search_path = public as $$
  select is_trip_owner(p_trip) or is_trip_co_admin(p_trip);
$$;

-- ---------- trips: owner + co-admin may edit content fields ----------
drop policy if exists trips_update on trips;

create policy trips_update on trips for update
  using (can_edit_trip_content(id));

create or replace function trips_update_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not is_trip_owner(old.id) then
    if new.owner_id is distinct from old.owner_id then
      raise exception 'only owner may change ownership';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trips_update_guard_trg on trips;
create trigger trips_update_guard_trg
  before update on trips
  for each row execute function trips_update_guard();

-- ---------- trip_members: only owner may update roster / roles ----------
-- (replaces members_owner_update from 0009 — same rule, explicit name)
drop policy if exists members_owner_update on trip_members;

create policy members_owner_update on trip_members for update
  using (is_trip_owner(trip_id))
  with check (is_trip_owner(trip_id));

-- ---------- owner-only role grant / revoke ----------
create or replace function set_member_role(
  p_trip_id uuid,
  p_user_id uuid,
  p_role member_role
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_target_role member_role;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  if not is_trip_owner(p_trip_id) then
    raise exception 'only trip owner may change roles';
  end if;
  if p_user_id = auth.uid() then
    raise exception 'cannot change your own role';
  end if;
  if p_role = 'owner'::member_role then
    raise exception 'cannot assign owner via set_member_role';
  end if;

  select m.role into v_target_role
  from trip_members m
  where m.trip_id = p_trip_id
    and m.user_id = p_user_id
    and m.status = 'active';

  if not found then
    raise exception 'active member not found';
  end if;
  if v_target_role = 'owner'::member_role then
    raise exception 'cannot change owner role';
  end if;

  update trip_members
  set role = p_role
  where trip_id = p_trip_id and user_id = p_user_id;
end;
$$;

revoke all on function set_member_role(uuid, uuid, member_role) from public;
grant execute on function set_member_role(uuid, uuid, member_role) to authenticated;
