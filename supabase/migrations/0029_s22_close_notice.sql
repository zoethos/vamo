-- S22 — per-member close notice, deemed-close clock, A1 settlement cutoff
-- Contract: docs/slices/S22_PROMPT.md, docs/design/CLOSURE_PATTERNS.md

-- ---------- member notice / nudge columns ----------
alter table trip_members
  add column if not exists close_notified_at timestamptz,
  add column if not exists close_reminded_at timestamptz,
  add column if not exists settle_nudged_at timestamptz;

-- ---------- guards: notice/nudge columns are RPC/service-only ----------
create or replace function trip_members_lifecycle_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' then
    if new.completed_at is distinct from old.completed_at
       or new.close_accepted_at is distinct from old.close_accepted_at
       or new.close_objected_at is distinct from old.close_objected_at
       or new.close_objection_reason is distinct from old.close_objection_reason
       or new.close_notified_at is distinct from old.close_notified_at
       or new.close_reminded_at is distinct from old.close_reminded_at
       or new.settle_nudged_at is distinct from old.settle_nudged_at then
      if coalesce(current_setting('vamo.lifecycle_rpc', true), '') <> '1' then
        raise exception 'member lifecycle fields require RPC';
      end if;
    end if;
  end if;
  return new;
end;
$$;

-- ---------- helpers ----------
create or replace function member_has_close_act(p_member trip_members) returns boolean
language sql immutable as $$
  select p_member.close_accepted_at is not null
      or p_member.close_objected_at is not null;
$$;

create or replace function member_deemed_close_ready(
  p_close_notified_at timestamptz,
  p_close_accepted_at timestamptz,
  p_close_objected_at timestamptz
) returns boolean
language sql stable as $$
  select p_close_accepted_at is not null
      or p_close_objected_at is not null
      or (
        p_close_notified_at is not null
        and p_close_notified_at + interval '14 days' <= now()
      );
$$;

create or replace function trip_all_members_deemed_ready(p_trip_id uuid) returns boolean
language sql security definer stable set search_path = public as $$
  select not exists (
    select 1
    from trip_members m
    where m.trip_id = p_trip_id
      and m.status = 'active'
      and not member_deemed_close_ready(
        m.close_notified_at,
        m.close_accepted_at,
        m.close_objected_at
      )
  );
$$;

create or replace function member_settlement_confirm_blocks_dispute(p_trip uuid, p_user uuid)
returns boolean
language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from settlements s
    where s.trip_id = p_trip
      and s.to_user = p_user
      and s.status = 'confirmed'::settlement_status
  );
$$;

create or replace function _stamp_member_close_notified(
  p_trip_id uuid,
  p_user_id uuid
) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform set_config('vamo.lifecycle_rpc', '1', true);
  update trip_members
  set close_notified_at = coalesce(close_notified_at, now())
  where trip_id = p_trip_id
    and user_id = p_user_id
    and status = 'active';
end;
$$;

-- In-app closing banner view = notice (MVP fallback when push unavailable)
create or replace function stamp_close_notice_viewed(p_trip_id uuid) returns void
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
  perform _stamp_member_close_notified(p_trip_id, auth.uid());
end;
$$;

revoke all on function stamp_close_notice_viewed(uuid) from public;
grant execute on function stamp_close_notice_viewed(uuid) to authenticated;

-- Service-role helper for cron / smoke
create or replace function rls_smoke_set_close_notified_at(
  p_trip_id uuid,
  p_user_id uuid,
  p_at timestamptz
) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform set_config('vamo.lifecycle_rpc', '1', true);
  update trip_members
  set close_notified_at = p_at
  where trip_id = p_trip_id and user_id = p_user_id;
end;
$$;

revoke all on function rls_smoke_set_close_notified_at(uuid, uuid, timestamptz) from public;
grant execute on function rls_smoke_set_close_notified_at(uuid, uuid, timestamptz) to service_role;

-- ---------- A1: settlement-confirm closes dispute window ----------
create or replace function respond_to_share(
  p_expense_id uuid,
  p_accept boolean,
  p_reason text default null
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_trip_id uuid;
  v_share_id uuid;
  v_trimmed text := nullif(trim(coalesce(p_reason, '')), '');
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  select e.trip_id into v_trip_id
  from expenses e
  where e.id = p_expense_id;

  if not found then
    raise exception 'expense not found';
  end if;
  if is_trip_cancelled(v_trip_id) then
    raise exception 'trip is cancelled';
  end if;
  if not exists (
    select 1 from trip_members m
    where m.trip_id = v_trip_id and m.user_id = v_uid and m.status = 'active'
  ) then
    raise exception 'not an active trip member';
  end if;

  if not p_accept
     and member_settlement_confirm_blocks_dispute(v_trip_id, v_uid) then
    raise exception 'dispute window closed after settlement confirm';
  end if;

  select s.id into v_share_id
  from expense_shares s
  where s.expense_id = p_expense_id and s.user_id = v_uid;

  if not found then
    raise exception 'no share row for caller';
  end if;

  if not p_accept and v_trimmed is null then
    raise exception 'reject requires a reason';
  end if;

  perform set_config('vamo.share_rpc', '1', true);
  update expense_shares
  set
    response = case
      when p_accept then 'accepted'::share_response
      else 'rejected'::share_response
    end,
    response_reason = case when p_accept then null else v_trimmed end,
    responded_at = now()
  where id = v_share_id;

  update expenses
  set spent_at = spent_at
  where id = p_expense_id;
end;
$$;

-- ---------- scheduled job (per-member deemed close clock) ----------
create or replace function run_trip_lifecycle_jobs() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_deemed int := 0;
  v_unresolved_warn int := 0;
  v_unresolved int := 0;
  v_settle_nudges int := 0;
  r record;
begin
  -- Deemed close: every active member acted OR (notified + 14d); no open objection
  for r in
    select t.id, t.owner_id
    from trips t
    where t.lifecycle = 'closing'
      and not trip_has_open_close_objection(t.id)
      and trip_all_members_deemed_ready(t.id)
  loop
    perform _close_trip(r.id, r.owner_id);
    v_deemed := v_deemed + 1;
  end loop;

  -- Settle nudge marker (push dispatched by edge fn; SQL marks eligible members once)
  for r in
    select m.trip_id, m.user_id
    from trip_members m
    join trips t on t.id = m.trip_id
    where m.status = 'active'
      and t.lifecycle = 'closed'
      and m.settle_nudged_at is null
      and exists (
        select 1
        from settlements s
        where s.trip_id = m.trip_id
          and s.status = 'marked'::settlement_status
          and (s.from_user = m.user_id or s.to_user = m.user_id)
      )
  loop
    perform set_config('vamo.lifecycle_rpc', '1', true);
    update trip_members
    set settle_nudged_at = now()
    where trip_id = r.trip_id and user_id = r.user_id;
    v_settle_nudges := v_settle_nudges + 1;
  end loop;

  -- Month 5 warn (objected trips only, once) — still anchored on close_requested_at
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
    'deemed_closed', v_deemed,
    'settle_nudges_marked', v_settle_nudges,
    'unresolved_warned', v_unresolved_warn,
    'unresolved', v_unresolved
  );
end;
$$;

-- Mark day-7 reminder sent (edge fn calls after push)
create or replace function mark_close_reminder_sent(
  p_trip_id uuid,
  p_user_id uuid
) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform set_config('vamo.lifecycle_rpc', '1', true);
  update trip_members
  set close_reminded_at = coalesce(close_reminded_at, now())
  where trip_id = p_trip_id
    and user_id = p_user_id
    and status = 'active';
end;
$$;

revoke all on function mark_close_reminder_sent(uuid, uuid) from public;
grant execute on function mark_close_reminder_sent(uuid, uuid) to service_role;

revoke all on function _stamp_member_close_notified(uuid, uuid) from public;
grant execute on function _stamp_member_close_notified(uuid, uuid) to service_role;
