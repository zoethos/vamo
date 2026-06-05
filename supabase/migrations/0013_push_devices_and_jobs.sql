-- S16 / R2 + scheduled-job proof (S17/S22 build on this)

-- ---------- FCM device tokens (one row per user + token) ----------
create table if not exists push_devices (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references profiles(id) on delete cascade,
  fcm_token    text not null,
  platform     text not null default 'android'
    check (platform in ('android', 'ios')),
  updated_at   timestamptz not null default now(),
  unique (user_id, fcm_token)
);

create index if not exists idx_push_devices_user on push_devices(user_id);

alter table push_devices enable row level security;

create policy push_devices_select on push_devices for select
  using (user_id = auth.uid());

create policy push_devices_insert on push_devices for insert
  with check (user_id = auth.uid());

create policy push_devices_update on push_devices for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy push_devices_delete on push_devices for delete
  using (user_id = auth.uid());

-- Upsert helper — keeps token fresh on app launch / refresh
create or replace function register_push_device(
  p_fcm_token text,
  p_platform text default 'android'
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_id uuid;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  if p_fcm_token is null or length(trim(p_fcm_token)) = 0 then
    raise exception 'token required';
  end if;
  if p_platform not in ('android', 'ios') then
    raise exception 'invalid platform';
  end if;

  insert into push_devices (user_id, fcm_token, platform, updated_at)
  values (v_uid, trim(p_fcm_token), p_platform, now())
  on conflict (user_id, fcm_token)
  do update set platform = excluded.platform, updated_at = now()
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function register_push_device(text, text) from public;
grant execute on function register_push_device(text, text) to authenticated;

-- ---------- scheduled job heartbeat (no-op proof for S17/S22) ----------
create table if not exists job_heartbeats (
  id         bigserial primary key,
  job_name   text not null,
  ran_at     timestamptz not null default now(),
  detail     text
);

create index if not exists idx_job_heartbeats_name on job_heartbeats(job_name, ran_at desc);

alter table job_heartbeats enable row level security;

-- Service role / edge function writes; authenticated may read recent heartbeats (debug)
create policy job_heartbeats_read on job_heartbeats for select
  using (auth.role() = 'authenticated');

create or replace function record_job_heartbeat(
  p_job_name text,
  p_detail text default null
) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_id bigint;
begin
  insert into job_heartbeats (job_name, detail)
  values (p_job_name, p_detail)
  returning id into v_id;
  return v_id;
end;
$$;

revoke all on function record_job_heartbeat(text, text) from public;
grant execute on function record_job_heartbeat(text, text) to service_role;

-- pg_cron: enable in Supabase Dashboard → Database → Extensions if available.
-- When enabled, schedule: select cron.schedule('vamo-heartbeat', '0 * * * *',
--   $$ select record_job_heartbeat('pg_cron', 'hourly noop'); $$);
-- Otherwise use Supabase scheduled Edge Function `scheduled-heartbeat` (see docs/SCHEDULED_JOBS.md).
