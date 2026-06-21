-- D-P1.a — Premium services control plane + POI/Foursquare first consumer.
--
-- Clients call edge functions; they never read config, usage, reservations, or
-- reusable provider caches directly. The edge function uses service_role and
-- SECURITY DEFINER RPCs for atomic quota reservations.

create table if not exists public.provider_config (
  service text not null,
  provider text not null,
  routing_priority integer not null default 100,
  enabled boolean not null default true,
  monthly_free_cap integer not null check (monthly_free_cap >= 0),
  default_free_quota integer not null check (default_free_quota >= 0),
  cache_ttl_seconds integer not null default 0 check (cache_ttl_seconds >= 0),
  can_cache_content boolean not null default false,
  can_cache_place_id boolean not null default true,
  can_store_photos boolean not null default false,
  requires_attribution boolean not null default false,
  requires_google_map boolean not null default false,
  max_retention_days integer check (max_retention_days is null or max_retention_days >= 0),
  config jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (service, provider)
);

comment on table public.provider_config is
  'D-P1.a premium-service provider routing, quota, and cache-policy config. Service-role/admin only.';

create table if not exists public.service_usage_global (
  service text not null,
  provider text not null,
  period_month date not null,
  fresh_calls integer not null default 0 check (fresh_calls >= 0),
  updated_at timestamptz not null default now(),
  primary key (service, provider, period_month)
);

create table if not exists public.service_usage_user (
  service text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  period_month date not null,
  fresh_calls integer not null default 0 check (fresh_calls >= 0),
  updated_at timestamptz not null default now(),
  primary key (service, user_id, period_month)
);

create table if not exists public.service_usage_reservations (
  id uuid primary key default extensions.gen_random_uuid(),
  idempotency_key text not null unique,
  service text not null,
  provider text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  period_month date not null,
  status text not null
    check (status in ('reserved', 'completed', 'failed', 'released')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists service_usage_reservations_user_period_idx
  on public.service_usage_reservations (service, user_id, period_month, created_at desc);

create table if not exists public.poi_cache (
  cache_key text primary key,
  provider text not null,
  geohash text not null,
  category text not null,
  results jsonb not null,
  fetched_at timestamptz not null default now(),
  expires_at timestamptz not null
);

create index if not exists poi_cache_expires_idx on public.poi_cache (expires_at);

create table if not exists public.premium_gate_notifications (
  user_id uuid not null references auth.users(id) on delete cascade,
  service text not null,
  period_month date not null,
  reason text not null,
  notification_id uuid references public.notifications(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (user_id, service, period_month, reason)
);

alter table public.provider_config enable row level security;
alter table public.service_usage_global enable row level security;
alter table public.service_usage_user enable row level security;
alter table public.service_usage_reservations enable row level security;
alter table public.poi_cache enable row level security;
alter table public.premium_gate_notifications enable row level security;

revoke all on public.provider_config from anon, authenticated;
revoke all on public.service_usage_global from anon, authenticated;
revoke all on public.service_usage_user from anon, authenticated;
revoke all on public.service_usage_reservations from anon, authenticated;
revoke all on public.poi_cache from anon, authenticated;
revoke all on public.premium_gate_notifications from anon, authenticated;

grant all privileges on public.provider_config to service_role;
grant all privileges on public.service_usage_global to service_role;
grant all privileges on public.service_usage_user to service_role;
grant all privileges on public.service_usage_reservations to service_role;
grant all privileges on public.poi_cache to service_role;
grant all privileges on public.premium_gate_notifications to service_role;

insert into public.provider_config (
  service,
  provider,
  routing_priority,
  enabled,
  monthly_free_cap,
  default_free_quota,
  cache_ttl_seconds,
  can_cache_content,
  can_cache_place_id,
  can_store_photos,
  requires_attribution,
  requires_google_map,
  max_retention_days,
  config
) values (
  'poi',
  'foursquare',
  10,
  true,
  8000,
  5,
  604800,
  true,
  true,
  false,
  false,
  false,
  null,
  '{"geohash_precision":6,"fields":"fsq_place_id,name,categories,latitude,longitude,location,distance"}'::jsonb
) on conflict (service, provider) do update set
  routing_priority = excluded.routing_priority,
  enabled = excluded.enabled,
  monthly_free_cap = excluded.monthly_free_cap,
  default_free_quota = excluded.default_free_quota,
  cache_ttl_seconds = excluded.cache_ttl_seconds,
  can_cache_content = excluded.can_cache_content,
  can_cache_place_id = excluded.can_cache_place_id,
  can_store_photos = excluded.can_store_photos,
  requires_attribution = excluded.requires_attribution,
  requires_google_map = excluded.requires_google_map,
  max_retention_days = excluded.max_retention_days,
  config = excluded.config,
  updated_at = now();

create or replace function public.reserve_service_usage(
  p_idempotency_key text,
  p_service text,
  p_user_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_period date := date_trunc('month', now())::date;
  v_existing service_usage_reservations%rowtype;
  v_config provider_config%rowtype;
  v_global_calls integer;
  v_user_calls integer;
  v_reservation_id uuid;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    raise exception 'missing idempotency key';
  end if;
  if p_service is null or length(trim(p_service)) = 0 then
    raise exception 'missing service';
  end if;
  if p_user_id is null then
    raise exception 'missing user';
  end if;

  select * into v_existing
  from service_usage_reservations
  where idempotency_key = p_idempotency_key
  for update;

  if found then
    return jsonb_build_object(
      'reserved', v_existing.status in ('reserved', 'completed'),
      'reservation_id', v_existing.id,
      'provider', v_existing.provider,
      'status', v_existing.status,
      'period_month', v_existing.period_month
    );
  end if;

  insert into service_usage_user (service, user_id, period_month, fresh_calls)
  values (p_service, p_user_id, v_period, 0)
  on conflict do nothing;

  select fresh_calls into v_user_calls
  from service_usage_user
  where service = p_service
    and user_id = p_user_id
    and period_month = v_period
  for update;

  for v_config in
    select *
    from provider_config
    where service = p_service
      and enabled
    order by routing_priority asc, provider asc
  loop
    if v_user_calls >= v_config.default_free_quota then
      return jsonb_build_object(
        'reserved', false,
        'gated', true,
        'reason', 'user_quota_exceeded',
        'period_month', v_period,
        'quota', v_config.default_free_quota
      );
    end if;

    insert into service_usage_global (service, provider, period_month, fresh_calls)
    values (p_service, v_config.provider, v_period, 0)
    on conflict do nothing;

    select fresh_calls into v_global_calls
    from service_usage_global
    where service = p_service
      and provider = v_config.provider
      and period_month = v_period
    for update;

    if v_global_calls >= v_config.monthly_free_cap then
      continue;
    end if;

    insert into service_usage_reservations (
      idempotency_key,
      service,
      provider,
      user_id,
      period_month,
      status
    ) values (
      p_idempotency_key,
      p_service,
      v_config.provider,
      p_user_id,
      v_period,
      'reserved'
    )
    returning id into v_reservation_id;

    update service_usage_user
    set fresh_calls = fresh_calls + 1,
        updated_at = now()
    where service = p_service
      and user_id = p_user_id
      and period_month = v_period;

    update service_usage_global
    set fresh_calls = fresh_calls + 1,
        updated_at = now()
    where service = p_service
      and provider = v_config.provider
      and period_month = v_period;

    return jsonb_build_object(
      'reserved', true,
      'reservation_id', v_reservation_id,
      'provider', v_config.provider,
      'period_month', v_period,
      'cache_ttl_seconds', v_config.cache_ttl_seconds,
      'can_cache_content', v_config.can_cache_content,
      'config', v_config.config
    );
  end loop;

  return jsonb_build_object(
    'reserved', false,
    'gated', true,
    'reason', 'provider_cap_exhausted',
    'period_month', v_period
  );
end;
$$;

create or replace function public.complete_service_usage_reservation(
  p_reservation_id uuid
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update service_usage_reservations
  set status = 'completed',
      updated_at = now()
  where id = p_reservation_id
    and status = 'reserved';
end;
$$;

create or replace function public.release_service_usage_reservation(
  p_reservation_id uuid,
  p_status text default 'released'
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row service_usage_reservations%rowtype;
begin
  if p_status not in ('failed', 'released') then
    raise exception 'invalid release status';
  end if;

  select * into v_row
  from service_usage_reservations
  where id = p_reservation_id
  for update;

  if not found or v_row.status <> 'reserved' then
    return;
  end if;

  update service_usage_reservations
  set status = p_status,
      updated_at = now()
  where id = p_reservation_id;

  update service_usage_user
  set fresh_calls = greatest(fresh_calls - 1, 0),
      updated_at = now()
  where service = v_row.service
    and user_id = v_row.user_id
    and period_month = v_row.period_month;

  update service_usage_global
  set fresh_calls = greatest(fresh_calls - 1, 0),
      updated_at = now()
  where service = v_row.service
    and provider = v_row.provider
    and period_month = v_row.period_month;
end;
$$;

create or replace function public.record_premium_gate_notification(
  p_user_id uuid,
  p_service text,
  p_reason text
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_period date := date_trunc('month', now())::date;
  v_notification_id uuid;
begin
  insert into premium_gate_notifications (user_id, service, period_month, reason)
  values (p_user_id, p_service, v_period, p_reason)
  on conflict do nothing;

  if not found then
    select notification_id into v_notification_id
    from premium_gate_notifications
    where user_id = p_user_id
      and service = p_service
      and period_month = v_period
      and reason = p_reason;
    return v_notification_id;
  end if;

  v_notification_id := record_notification(
    p_user_id,
    null,
    'premium_gate',
    'More place lookups with Vamo Plus',
    'You have used your free place lookups this month. Manual places still work.',
    '/profile'
  );

  update premium_gate_notifications
  set notification_id = v_notification_id
  where user_id = p_user_id
    and service = p_service
    and period_month = v_period
    and reason = p_reason;

  return v_notification_id;
end;
$$;

revoke all on function public.reserve_service_usage(text, text, uuid) from public;
revoke all on function public.complete_service_usage_reservation(uuid) from public;
revoke all on function public.release_service_usage_reservation(uuid, text) from public;
revoke all on function public.record_premium_gate_notification(uuid, text, text) from public;

grant execute on function public.reserve_service_usage(text, text, uuid) to service_role;
grant execute on function public.complete_service_usage_reservation(uuid) to service_role;
grant execute on function public.release_service_usage_reservation(uuid, text) to service_role;
grant execute on function public.record_premium_gate_notification(uuid, text, text) to service_role;
