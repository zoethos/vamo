-- S48 — auto soft-close on end date (writable, owner-notice, isolated from deemed-close).

alter table trips
  add column if not exists soft_closed_at timestamptz,
  add column if not exists soft_closed_by uuid references profiles(id),
  add column if not exists reopened_at timestamptz;

create or replace function is_trip_writable(p_trip uuid) returns boolean
language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from trips t
    where t.id = p_trip
      and t.lifecycle in ('active', 'closing', 'soft_closed')
  );
$$;

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
       or new.unresolved_warned_at is distinct from old.unresolved_warned_at
       or new.soft_closed_at is distinct from old.soft_closed_at
       or new.soft_closed_by is distinct from old.soft_closed_by
       or new.reopened_at is distinct from old.reopened_at then
      if coalesce(current_setting('vamo.lifecycle_rpc', true), '') <> '1' then
        raise exception 'lifecycle changes require RPC';
      end if;
    end if;
  end if;
  return new;
end;
$$;

create or replace function trips_update_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.theme is distinct from old.theme
     and coalesce(current_setting('vamo.theme_rpc', true), '') <> '1' then
    raise exception 'trip theme requires resolver';
  end if;

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
       or new.unresolved_warned_at is distinct from old.unresolved_warned_at
       or new.soft_closed_at is distinct from old.soft_closed_at
       or new.soft_closed_by is distinct from old.soft_closed_by
       or new.reopened_at is distinct from old.reopened_at)
       and coalesce(current_setting('vamo.lifecycle_rpc', true), '') <> '1' then
      raise exception 'co-admin cannot change trip lifecycle';
    end if;
  end if;
  return new;
end;
$$;

create or replace function _enter_soft_close(p_trip_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_owner uuid;
begin
  select owner_id into v_owner
  from trips
  where id = p_trip_id and lifecycle = 'active';

  if not found then
    return;
  end if;

  perform set_config('vamo.lifecycle_rpc', '1', true);
  update trips
  set lifecycle = 'soft_closed',
      soft_closed_at = now(),
      soft_closed_by = v_owner
  where id = p_trip_id
    and lifecycle = 'active';
end;
$$;

revoke all on function _enter_soft_close(uuid) from public;
grant execute on function _enter_soft_close(uuid) to service_role;

create or replace function reopen_from_soft_close(p_trip_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  if not is_trip_owner(p_trip_id) then
    raise exception 'only owner may reopen trip';
  end if;
  if not exists (
    select 1 from trips
    where id = p_trip_id
      and lifecycle = 'soft_closed'
      and close_requested_at is null
  ) then
    raise exception 'trip must be soft_closed without pending close';
  end if;

  perform set_config('vamo.lifecycle_rpc', '1', true);
  update trips
  set lifecycle = 'active',
      soft_closed_at = null,
      soft_closed_by = null,
      reopened_at = now()
  where id = p_trip_id;
end;
$$;

revoke all on function reopen_from_soft_close(uuid) from public;
grant execute on function reopen_from_soft_close(uuid) to authenticated;

create unique index if not exists idx_notifications_wrapped_trip_once
  on notifications (user_id, trip_id)
  where type = 'wrapped_trip';
