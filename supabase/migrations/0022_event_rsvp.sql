-- S21 / R8 — event RSVP on trip_plan_items (kind=activity); no events table.

do $$ begin
  create type rsvp_status as enum ('going', 'maybe', 'declined');
exception when duplicate_object then null; end $$;

create table if not exists trip_plan_item_rsvps (
  id            uuid primary key default gen_random_uuid(),
  plan_item_id  uuid not null references trip_plan_items(id) on delete cascade,
  user_id       uuid not null references profiles(id),
  status        rsvp_status not null,
  responded_at  timestamptz not null default now(),
  unique (plan_item_id, user_id)
);

create index if not exists idx_trip_plan_item_rsvps_plan
  on trip_plan_item_rsvps(plan_item_id);

alter table trip_plan_item_rsvps enable row level security;

-- ---------- GUC guard (RPC-only writes) ----------
create or replace function trip_plan_item_rsvps_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(current_setting('vamo.rsvp_rpc', true), '') <> '1' then
    raise exception 'rsvp changes require RPC';
  end if;
  return new;
end;
$$;

drop trigger if exists trip_plan_item_rsvps_guard_trg on trip_plan_item_rsvps;
create trigger trip_plan_item_rsvps_guard_trg
  before insert or update on trip_plan_item_rsvps
  for each row execute function trip_plan_item_rsvps_guard();

-- ---------- RLS ----------
drop policy if exists trip_plan_item_rsvps_select on trip_plan_item_rsvps;
create policy trip_plan_item_rsvps_select on trip_plan_item_rsvps
  for select using (
    exists (
      select 1 from trip_plan_items p
      where p.id = plan_item_id and is_trip_member(p.trip_id)
    )
  );

drop policy if exists trip_plan_item_rsvps_insert on trip_plan_item_rsvps;
create policy trip_plan_item_rsvps_insert on trip_plan_item_rsvps
  for insert with check (
    user_id = auth.uid()
    and exists (
      select 1 from trip_plan_items p
      where p.id = plan_item_id
        and is_trip_member(p.trip_id)
        and is_trip_writable(p.trip_id)
    )
  );

drop policy if exists trip_plan_item_rsvps_update on trip_plan_item_rsvps;
create policy trip_plan_item_rsvps_update on trip_plan_item_rsvps
  for update
  using (
    user_id = auth.uid()
    and exists (
      select 1 from trip_plan_items p
      where p.id = plan_item_id and is_trip_member(p.trip_id)
    )
  )
  with check (
    user_id = auth.uid()
    and exists (
      select 1 from trip_plan_items p
      where p.id = plan_item_id
        and is_trip_member(p.trip_id)
        and is_trip_writable(p.trip_id)
    )
  );

drop policy if exists trip_plan_item_rsvps_delete on trip_plan_item_rsvps;
create policy trip_plan_item_rsvps_delete on trip_plan_item_rsvps
  for delete using (
    user_id = auth.uid()
    and exists (
      select 1 from trip_plan_items p
      where p.id = plan_item_id and is_trip_member(p.trip_id)
    )
  );

drop policy if exists trip_plan_item_rsvps_block_delete_closed on trip_plan_item_rsvps;
create policy trip_plan_item_rsvps_block_delete_closed on trip_plan_item_rsvps
  as restrictive for delete using (
    exists (
      select 1 from trip_plan_items p
      where p.id = plan_item_id and is_trip_writable(p.trip_id)
    )
  );

-- ---------- public RPC ----------
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
end;
$$;

revoke all on function set_event_rsvp(uuid, rsvp_status) from public;
grant execute on function set_event_rsvp(uuid, rsvp_status) to authenticated;

do $$ begin
  alter publication supabase_realtime add table public.trip_plan_item_rsvps;
exception when duplicate_object then null;
end $$;
