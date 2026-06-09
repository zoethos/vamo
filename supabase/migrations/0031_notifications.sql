-- S46 — in-app notification center (record-first; push best-effort)

create table public.notifications (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  trip_id uuid references public.trips(id) on delete cascade,
  type text not null,
  title text not null,
  body text not null,
  route text,
  created_at timestamptz not null default now(),
  read_at timestamptz
);

create index notifications_user_created_idx
  on public.notifications (user_id, created_at desc);

create index notifications_user_unread_idx
  on public.notifications (user_id)
  where read_at is null;

alter table public.notifications enable row level security;

create policy notifications_select_own on public.notifications
  for select to authenticated
  using (user_id = auth.uid());

-- No INSERT/UPDATE/DELETE policies for authenticated — service RPCs only.

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
  returning id into v_id;
  return v_id;
end;
$$;

revoke all on function record_notification(uuid, uuid, text, text, text, text) from public;
grant execute on function record_notification(uuid, uuid, text, text, text, text)
  to service_role;

create or replace function mark_notification_read(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  update notifications
  set read_at = coalesce(read_at, now())
  where id = p_id and user_id = auth.uid();
end;
$$;

revoke all on function mark_notification_read(uuid) from public;
grant execute on function mark_notification_read(uuid) to authenticated;

create or replace function mark_all_notifications_read() returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  update notifications
  set read_at = coalesce(read_at, now())
  where user_id = auth.uid() and read_at is null;
end;
$$;

revoke all on function mark_all_notifications_read() from public;
grant execute on function mark_all_notifications_read() to authenticated;
