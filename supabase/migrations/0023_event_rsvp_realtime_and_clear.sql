-- S21 review fixes — parent-touch for realtime, clear_event_rsvp, DELETE guard.
-- 0022 is already applied on cloud; do not edit it.

-- ---------- GUC guard: RPC-only writes (INSERT/UPDATE/DELETE) ----------
create or replace function trip_plan_item_rsvps_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(current_setting('vamo.rsvp_rpc', true), '') <> '1' then
    raise exception 'rsvp changes require RPC';
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists trip_plan_item_rsvps_guard_trg on trip_plan_item_rsvps;
create trigger trip_plan_item_rsvps_guard_trg
  before insert or update or delete on trip_plan_item_rsvps
  for each row execute function trip_plan_item_rsvps_guard();

-- ---------- set_event_rsvp: upsert + parent touch for trip-scoped realtime ----------
create or replace function set_event_rsvp(
  p_plan_item_id uuid,
  p_status rsvp_status
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_trip_id uuid;
  v_kind plan_item_kind;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  select p.trip_id, p.kind into v_trip_id, v_kind
  from trip_plan_items p
  where p.id = p_plan_item_id;

  if not found then
    raise exception 'plan item not found';
  end if;
  if v_kind <> 'activity'::plan_item_kind then
    raise exception 'RSVP only for activity events';
  end if;
  if not is_trip_member(v_trip_id) then
    raise exception 'not a trip member';
  end if;
  if not is_trip_writable(v_trip_id) then
    raise exception 'trip is read-only';
  end if;

  perform set_config('vamo.rsvp_rpc', '1', true);

  insert into trip_plan_item_rsvps (
    plan_item_id, user_id, status, responded_at
  ) values (
    p_plan_item_id, v_uid, p_status, now()
  )
  on conflict (plan_item_id, user_id) do update
  set status = excluded.status,
      responded_at = excluded.responded_at;

  -- Touch parent so trip_plan_items realtime subscription refreshes peers.
  update trip_plan_items
  set updated_at = now()
  where id = p_plan_item_id;
end;
$$;

revoke all on function set_event_rsvp(uuid, rsvp_status) from public;
grant execute on function set_event_rsvp(uuid, rsvp_status) to authenticated;

-- ---------- clear_event_rsvp: own-row withdraw + parent touch ----------
create or replace function clear_event_rsvp(p_plan_item_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_trip_id uuid;
  v_kind plan_item_kind;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  select p.trip_id, p.kind into v_trip_id, v_kind
  from trip_plan_items p
  where p.id = p_plan_item_id;

  if not found then
    raise exception 'plan item not found';
  end if;
  if v_kind <> 'activity'::plan_item_kind then
    raise exception 'RSVP only for activity events';
  end if;
  if not is_trip_member(v_trip_id) then
    raise exception 'not a trip member';
  end if;
  if not is_trip_writable(v_trip_id) then
    raise exception 'trip is read-only';
  end if;

  perform set_config('vamo.rsvp_rpc', '1', true);

  delete from trip_plan_item_rsvps
  where plan_item_id = p_plan_item_id and user_id = v_uid;

  update trip_plan_items
  set updated_at = now()
  where id = p_plan_item_id;
end;
$$;

revoke all on function clear_event_rsvp(uuid) from public;
grant execute on function clear_event_rsvp(uuid) to authenticated;
