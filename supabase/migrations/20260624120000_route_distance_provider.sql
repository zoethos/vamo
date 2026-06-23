-- Slice 4.1 — OpenRouteService road-distance feasibility for draft-trip-route.
--
-- Registers a `route-distance` service in the premium control plane and a cache
-- keyed by coordinate-pair + routing profile. The draft-trip-route function
-- calls ORS as a best-effort enhancement over the straight-line haversine check;
-- it degrades to straight-line when ORS is unconfigured, gated, or fails.
-- Secrets:
--   VAMO_OPENROUTESERVICE_STAGING_API_KEY=...   (staging project)
--   VAMO_OPENROUTESERVICE_PROD_API_KEY=...      (production project)
--   VAMO_OPENROUTESERVICE_API_KEY=...           (optional shared alias)

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
  'route-distance',
  'openrouteservice',
  10,
  true,
  2000,         -- monthly_free_cap: global fresh ORS calls/month (free tier ~2k/day)
  30,           -- default_free_quota: fresh ORS calls per user per month
  7776000,      -- cache_ttl_seconds: 90 days — road distance for a coord pair is stable
  true,
  true,
  false,
  true,         -- requires_attribution: ORS results need attribution in-product
  false,
  null,
  '{"adapter":"ors-matrix","base_url":"https://api.openrouteservice.org/","timeout_ms":8000}'::jsonb
) on conflict (service, provider) do update set
  routing_priority = excluded.routing_priority,
  enabled = excluded.enabled,
  monthly_free_cap = excluded.monthly_free_cap,
  default_free_quota = excluded.default_free_quota,
  cache_ttl_seconds = excluded.cache_ttl_seconds,
  can_cache_content = excluded.can_cache_content,
  requires_attribution = excluded.requires_attribution,
  config = excluded.config,
  updated_at = now();

-- Reusable, long-lived cache of road distance for a (from, to, profile) pair.
create table if not exists public.route_distance_cache (
  cache_key text primary key,
  profile text not null,
  distance_m integer not null check (distance_m >= 0),
  fetched_at timestamptz not null default now(),
  expires_at timestamptz not null
);

create index if not exists route_distance_cache_expires_idx
  on public.route_distance_cache (expires_at);

alter table public.route_distance_cache enable row level security;
revoke all on public.route_distance_cache from anon, authenticated;
grant all privileges on public.route_distance_cache to service_role;
