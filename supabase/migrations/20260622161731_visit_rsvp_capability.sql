-- Allow Visit plan items to use the same RSVP surface as activity events.
-- This keeps the server RPC contract and data-driven capabilities aligned with
-- the client fallback introduced with the Plan timeline.

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
  if v_kind not in ('activity'::plan_item_kind, 'visit'::plan_item_kind) then
    raise exception 'RSVP only for activity or visit events';
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

  update trip_plan_items
  set updated_at = now()
  where id = p_plan_item_id;
end;
$$;

revoke all on function set_event_rsvp(uuid, rsvp_status) from public;
grant execute on function set_event_rsvp(uuid, rsvp_status) to authenticated;

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
  if v_kind not in ('activity'::plan_item_kind, 'visit'::plan_item_kind) then
    raise exception 'RSVP only for activity or visit events';
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

insert into public.plan_item_capabilities (
  kind,
  wave_min,
  supports_rsvp,
  suggests_pois,
  has_live_status,
  has_check_times,
  sells_tickets,
  has_details_form
) values
  ('visit', 2, true, true, false, false, false, true)
on conflict (kind) do update set
  wave_min = excluded.wave_min,
  supports_rsvp = excluded.supports_rsvp,
  suggests_pois = excluded.suggests_pois,
  has_live_status = excluded.has_live_status,
  has_check_times = excluded.has_check_times,
  sells_tickets = excluded.sells_tickets,
  has_details_form = excluded.has_details_form;
