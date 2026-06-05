-- S17 / R3 — trip lifecycle (deemed acceptance closure dance)
-- Contract: docs/workflows/trip-closure.md

-- ---------- enum ----------
do $$ begin
  create type trip_lifecycle as enum (
    'active', 'cancelled', 'closing', 'closed', 'unresolved'
  );
exception when duplicate_object then null; end $$;

-- ---------- columns ----------
alter table trips
  add column if not exists lifecycle trip_lifecycle not null default 'active',
  add column if not exists closed_at timestamptz,
  add column if not exists closed_by uuid references profiles(id),
  add column if not exists cancelled_at timestamptz,
  add column if not exists cancelled_by uuid references profiles(id),
  add column if not exists close_requested_at timestamptz,
  add column if not exists close_warned_at timestamptz,
  add column if not exists unresolved_warned_at timestamptz;

alter table trip_members
  add column if not exists completed_at timestamptz,
  add column if not exists close_accepted_at timestamptz,
  add column if not exists close_objected_at timestamptz,
  add column if not exists close_objection_reason text;

-- ---------- helpers ----------
create or replace function is_trip_closed(p_trip uuid) returns boolean
language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from trips t
    where t.id = p_trip
      and t.lifecycle in ('closed', 'unresolved', 'cancelled')
  );
$$;

create or replace function is_trip_writable(p_trip uuid) returns boolean
language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from trips t
    where t.id = p_trip
      and t.lifecycle in ('active', 'closing')
  );
$$;

create or replace function is_trip_cancelled(p_trip uuid) returns boolean
language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from trips t
    where t.id = p_trip and t.lifecycle = 'cancelled'
  );
$$;

create or replace function trip_has_open_close_objection(p_trip uuid) returns boolean
language sql security definer stable set search_path = public as $$
  select exists (
    select 1
    from trip_members m
    join trips t on t.id = m.trip_id
    where m.trip_id = p_trip
      and m.status = 'active'
      and t.lifecycle = 'closing'
      and m.close_objected_at is not null
  );
$$;

create or replace function is_active_trip_member(p_trip uuid, p_user uuid) returns boolean
language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from trip_members m
    where m.trip_id = p_trip
      and m.user_id = p_user
      and m.status = 'active'
  );
$$;

-- ---------- lifecycle column guard (RPC-only transitions) ----------
create or replace function trips_lifecycle_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' then
    if new.lifecycle is distinct from old.lifecycle
       or new.closed_at is distinct from old.closed_at
       or new.closed_by is distinct from old.closed_by
       or new.cancelled_at is distinct from old.cancelled_at
       or new.cancelled_by is distinct from old.cancelled_by
       or new.close_requested_at is distinct from old.close_requested_at
       or new.close_warned_at is distinct from old.close_warned_at
       or new.unresolved_warned_at is distinct from old.unresolved_warned_at then
      if coalesce(current_setting('vamo.lifecycle_rpc', true), '') <> '1' then
        raise exception 'lifecycle changes require RPC';
      end if;
      -- No owner check here: inside the RPC flag, RPCs/jobs self-authorize
      -- (members legitimately drive auto-closing/early-close transitions;
      -- the cron job runs as service role with auth.uid() = null).
      -- Outside the flag, the exception above already blocks everyone.
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trips_lifecycle_guard_trg on trips;
create trigger trips_lifecycle_guard_trg
  before update on trips
  for each row execute function trips_lifecycle_guard();

-- Extend content guard: co-admin cannot touch lifecycle columns (belt + suspenders)
create or replace function trips_update_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not is_trip_owner(old.id) then
    if new.owner_id is distinct from old.owner_id then
      raise exception 'only owner may change ownership';
    end if;
    if (new.lifecycle is distinct from old.lifecycle
       or new.closed_at is distinct from old.closed_at
       or new.closed_by is distinct from old.closed_by
       or new.cancelled_at is distinct from old.cancelled_at
       or new.cancelled_by is distinct from old.cancelled_by
       or new.close_requested_at is distinct from old.close_requested_at
       or new.close_warned_at is distinct from old.close_warned_at
       or new.unresolved_warned_at is distinct from old.unresolved_warned_at)
       and coalesce(current_setting('vamo.lifecycle_rpc', true), '') <> '1' then
      raise exception 'co-admin cannot change trip lifecycle';
    end if;
  end if;
  return new;
end;
$$;

-- Member lifecycle columns: RPC-only
create or replace function trip_members_lifecycle_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' then
    if new.completed_at is distinct from old.completed_at
       or new.close_accepted_at is distinct from old.close_accepted_at
       or new.close_objected_at is distinct from old.close_objected_at
       or new.close_objection_reason is distinct from old.close_objection_reason then
      if coalesce(current_setting('vamo.lifecycle_rpc', true), '') <> '1' then
        raise exception 'member lifecycle fields require RPC';
      end if;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trip_members_lifecycle_guard_trg on trip_members;
create trigger trip_members_lifecycle_guard_trg
  before update on trip_members
  for each row execute function trip_members_lifecycle_guard();

-- ---------- RLS: read-only after close ----------
drop policy if exists expenses_all on expenses;
create policy expenses_all on expenses for all
  using (is_trip_member(trip_id))
  with check (is_trip_member(trip_id) and is_trip_writable(trip_id));

drop policy if exists shares_all on expense_shares;
create policy shares_all on expense_shares for all
  using (
    exists (
      select 1 from expenses e
      where e.id = expense_id and is_trip_member(e.trip_id)
    )
  )
  with check (
    exists (
      select 1 from expenses e
      where e.id = expense_id
        and is_trip_member(e.trip_id)
        and is_trip_writable(e.trip_id)
    )
  );

-- Settlements: 0007's participant-scoped policies stay AUTHORITATIVE
-- (recreating settlements_all here would let any member write others'
-- settlements — S17 review P1-3). Cancellation block is RESTRICTIVE
-- (ANDed on top): settling stays open in closing/closed/unresolved.
drop policy if exists settlements_block_cancelled_ins on settlements;
create policy settlements_block_cancelled_ins on settlements
  as restrictive for insert
  with check (not is_trip_cancelled(trip_id));

drop policy if exists settlements_block_cancelled_upd on settlements;
create policy settlements_block_cancelled_upd on settlements
  as restrictive for update
  using (not is_trip_cancelled(trip_id));

drop policy if exists settlements_block_cancelled_del on settlements;
create policy settlements_block_cancelled_del on settlements
  as restrictive for delete
  using (not is_trip_cancelled(trip_id));

drop policy if exists trip_notes_all on trip_notes;
create policy trip_notes_all on trip_notes for all
  using (is_trip_member(trip_id))
  with check (is_trip_member(trip_id) and is_trip_writable(trip_id));

drop policy if exists trip_photos_all on trip_photos;
create policy trip_photos_all on trip_photos for all
  using (is_trip_member(trip_id))
  with check (is_trip_member(trip_id) and is_trip_writable(trip_id));

drop policy if exists places_all on places;
create policy places_all on places for all
  using (is_trip_member(trip_id))
  with check (is_trip_member(trip_id) and is_trip_writable(trip_id));

-- DELETE after close: FOR ALL policies apply USING to deletes, and USING
-- must stay member-wide for SELECT — so deletes need RESTRICTIVE guards
-- (S17 review P1-4).
drop policy if exists expenses_block_delete_closed on expenses;
create policy expenses_block_delete_closed on expenses
  as restrictive for delete
  using (is_trip_writable(trip_id));

drop policy if exists shares_block_delete_closed on expense_shares;
create policy shares_block_delete_closed on expense_shares
  as restrictive for delete
  using (
    exists (
      select 1 from expenses e
      where e.id = expense_id and is_trip_writable(e.trip_id)
    )
  );

drop policy if exists trip_notes_block_delete_closed on trip_notes;
create policy trip_notes_block_delete_closed on trip_notes
  as restrictive for delete
  using (is_trip_writable(trip_id));

drop policy if exists trip_photos_block_delete_closed on trip_photos;
create policy trip_photos_block_delete_closed on trip_photos
  as restrictive for delete
  using (is_trip_writable(trip_id));

drop policy if exists places_block_delete_closed on places;
create policy places_block_delete_closed on places
  as restrictive for delete
  using (is_trip_writable(trip_id));

-- Storage captures: block writes when trip not writable
drop policy if exists captures_insert on storage.objects;
create policy captures_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'captures'
    and (storage.foldername(name))[1] = auth.uid()::text
    and public.is_trip_member(((storage.foldername(name))[2])::uuid)
    and public.is_trip_writable(((storage.foldername(name))[2])::uuid)
  );

drop policy if exists captures_update on storage.objects;
create policy captures_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'captures'
    and (storage.foldername(name))[1] = auth.uid()::text
    and public.is_trip_member(((storage.foldername(name))[2])::uuid)
    and public.is_trip_writable(((storage.foldername(name))[2])::uuid)
  );

-- 0005's captures_delete had no trip-state gate (S17 review P1-4)
drop policy if exists captures_delete on storage.objects;
create policy captures_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'captures'
    and (storage.foldername(name))[1] = auth.uid()::text
    and public.is_trip_writable(((storage.foldername(name))[2])::uuid)
  );

-- ---------- internal lifecycle helpers ----------
create or replace function _enter_closing(p_trip_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform set_config('vamo.lifecycle_rpc', '1', true);
  update trips
  set lifecycle = 'closing',
      close_requested_at = coalesce(close_requested_at, now())
  where id = p_trip_id
    and lifecycle = 'active';
end;
$$;

create or replace function _close_trip(
  p_trip_id uuid,
  p_closed_by uuid
) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform set_config('vamo.lifecycle_rpc', '1', true);
  update trips
  set lifecycle = 'closed',
      closed_at = now(),
      closed_by = p_closed_by
  where id = p_trip_id
    and lifecycle = 'closing';
end;
$$;

create or replace function _all_active_members_completed(p_trip_id uuid) returns boolean
language sql security definer stable set search_path = public as $$
  select not exists (
    select 1 from trip_members m
    where m.trip_id = p_trip_id
      and m.status = 'active'
      and m.completed_at is null
  );
$$;

create or replace function _all_active_members_accepted_close(p_trip_id uuid) returns boolean
language sql security definer stable set search_path = public as $$
  select not exists (
    select 1 from trip_members m
    where m.trip_id = p_trip_id
      and m.status = 'active'
      and m.close_accepted_at is null
  );
$$;

-- ---------- authenticated RPCs ----------
create or replace function request_trip_close(p_trip_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if not is_trip_owner(p_trip_id) then
    raise exception 'only owner may request close';
  end if;
  if not exists (
    select 1 from trips where id = p_trip_id and lifecycle = 'active'
  ) then
    raise exception 'trip must be active';
  end if;
  perform _enter_closing(p_trip_id);
end;
$$;

create or replace function mark_trip_member_complete(p_trip_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if not is_active_trip_member(p_trip_id, auth.uid()) then
    raise exception 'not an active member';
  end if;
  if not exists (
    select 1 from trips where id = p_trip_id and lifecycle = 'active'
  ) then
    raise exception 'trip must be active';
  end if;

  perform set_config('vamo.lifecycle_rpc', '1', true);
  update trip_members
  set completed_at = coalesce(completed_at, now())
  where trip_id = p_trip_id and user_id = auth.uid() and status = 'active';

  if _all_active_members_completed(p_trip_id) then
    perform _enter_closing(p_trip_id);
  end if;
end;
$$;

create or replace function accept_trip_close(p_trip_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if not is_active_trip_member(p_trip_id, auth.uid()) then
    raise exception 'not an active member';
  end if;
  if not exists (
    select 1 from trips where id = p_trip_id and lifecycle = 'closing'
  ) then
    raise exception 'trip is not closing';
  end if;

  perform set_config('vamo.lifecycle_rpc', '1', true);
  update trip_members
  set close_accepted_at = coalesce(close_accepted_at, now()),
      close_objected_at = null,
      close_objection_reason = null
  where trip_id = p_trip_id and user_id = auth.uid() and status = 'active';

  if _all_active_members_accepted_close(p_trip_id) then
    perform _close_trip(p_trip_id, (
      select owner_id from trips where id = p_trip_id
    ));
  end if;
end;
$$;

create or replace function object_to_trip_close(
  p_trip_id uuid,
  p_reason text
) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason required';
  end if;
  if not is_active_trip_member(p_trip_id, auth.uid()) then
    raise exception 'not an active member';
  end if;
  if not exists (
    select 1 from trips where id = p_trip_id and lifecycle = 'closing'
  ) then
    raise exception 'trip is not closing';
  end if;

  perform set_config('vamo.lifecycle_rpc', '1', true);
  update trip_members
  set close_objected_at = now(),
      close_objection_reason = trim(p_reason),
      close_accepted_at = null
  where trip_id = p_trip_id and user_id = auth.uid() and status = 'active';
end;
$$;

create or replace function withdraw_close_objection(p_trip_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if not is_active_trip_member(p_trip_id, auth.uid()) then
    raise exception 'not an active member';
  end if;
  if not exists (
    select 1 from trips where id = p_trip_id and lifecycle = 'closing'
  ) then
    raise exception 'trip is not closing';
  end if;

  perform set_config('vamo.lifecycle_rpc', '1', true);
  update trip_members
  set close_objected_at = null,
      close_objection_reason = null
  where trip_id = p_trip_id and user_id = auth.uid() and status = 'active';
end;
$$;

create or replace function force_close_trip(p_trip_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_owner uuid;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if not is_trip_owner(p_trip_id) then
    raise exception 'only owner may force close';
  end if;
  if not exists (
    select 1 from trips where id = p_trip_id and lifecycle = 'closing'
  ) then
    raise exception 'trip is not closing';
  end if;

  select owner_id into v_owner from trips where id = p_trip_id;
  perform _close_trip(p_trip_id, v_owner);
end;
$$;

create or replace function cancel_trip(p_trip_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if not is_trip_owner(p_trip_id) then
    raise exception 'only owner may cancel';
  end if;
  if not exists (
    select 1 from trips t
    where t.id = p_trip_id
      and t.lifecycle = 'active'
      and (t.start_date is null or t.start_date > current_date)
  ) then
    raise exception 'trip cannot be cancelled';
  end if;

  perform set_config('vamo.lifecycle_rpc', '1', true);
  update trips
  set lifecycle = 'cancelled',
      cancelled_at = now(),
      cancelled_by = auth.uid()
  where id = p_trip_id;
end;
$$;

revoke all on function request_trip_close(uuid) from public;
revoke all on function mark_trip_member_complete(uuid) from public;
revoke all on function accept_trip_close(uuid) from public;
revoke all on function object_to_trip_close(uuid, text) from public;
revoke all on function withdraw_close_objection(uuid) from public;
revoke all on function force_close_trip(uuid) from public;
revoke all on function cancel_trip(uuid) from public;

grant execute on function request_trip_close(uuid) to authenticated;
grant execute on function mark_trip_member_complete(uuid) to authenticated;
grant execute on function accept_trip_close(uuid) to authenticated;
grant execute on function object_to_trip_close(uuid, text) to authenticated;
grant execute on function withdraw_close_objection(uuid) to authenticated;
grant execute on function force_close_trip(uuid) to authenticated;
grant execute on function cancel_trip(uuid) to authenticated;

-- ---------- scheduled job (service role / edge cron) ----------
create or replace function run_trip_lifecycle_jobs() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_day7 int := 0;
  v_deemed int := 0;
  v_unresolved_warn int := 0;
  v_unresolved int := 0;
  r record;
begin
  -- Day 7 reminder (once per trip via close_warned_at)
  for r in
    select id from trips
    where lifecycle = 'closing'
      and close_requested_at is not null
      and close_requested_at + interval '7 days' <= now()
      and close_warned_at is null
  loop
    perform set_config('vamo.lifecycle_rpc', '1', true);
    update trips set close_warned_at = now() where id = r.id;
    v_day7 := v_day7 + 1;
  end loop;

  -- Day 14 deemed close (no open objection)
  for r in
    select id, owner_id from trips
    where lifecycle = 'closing'
      and close_requested_at is not null
      and close_requested_at + interval '14 days' <= now()
      and not trip_has_open_close_objection(id)
  loop
    perform _close_trip(r.id, r.owner_id);
    v_deemed := v_deemed + 1;
  end loop;

  -- Month 5 warn (objected trips only, once)
  for r in
    select id from trips
    where lifecycle = 'closing'
      and close_requested_at is not null
      and close_requested_at + interval '5 months' <= now()
      and trip_has_open_close_objection(id)
      and unresolved_warned_at is null
  loop
    perform set_config('vamo.lifecycle_rpc', '1', true);
    update trips set unresolved_warned_at = now() where id = r.id;
    v_unresolved_warn := v_unresolved_warn + 1;
  end loop;

  -- Month 6 auto-unresolved (objected trips only)
  for r in
    select id from trips
    where lifecycle = 'closing'
      and close_requested_at is not null
      and close_requested_at + interval '6 months' <= now()
      and trip_has_open_close_objection(id)
  loop
    perform set_config('vamo.lifecycle_rpc', '1', true);
    update trips
    set lifecycle = 'unresolved',
        closed_at = now(),
        closed_by = owner_id
    where id = r.id;
    v_unresolved := v_unresolved + 1;
  end loop;

  return jsonb_build_object(
    'day7_reminders', v_day7,
    'deemed_closed', v_deemed,
    'unresolved_warned', v_unresolved_warn,
    'unresolved', v_unresolved
  );
end;
$$;

revoke all on function run_trip_lifecycle_jobs() from public;
grant execute on function run_trip_lifecycle_jobs() to service_role;

-- Smoke / ops: backdate close window (service role only)
create or replace function rls_smoke_set_close_requested_at(
  p_trip_id uuid,
  p_at timestamptz
) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform set_config('vamo.lifecycle_rpc', '1', true);
  update trips
  set close_requested_at = p_at,
      close_warned_at = null
  where id = p_trip_id and lifecycle = 'closing';
end;
$$;

revoke all on function rls_smoke_set_close_requested_at(uuid, timestamptz) from public;
grant execute on function rls_smoke_set_close_requested_at(uuid, timestamptz) to service_role;
