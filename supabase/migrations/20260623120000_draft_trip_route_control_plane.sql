-- Slice 2 — Advanced Travel Planning: draft-trip-route AI drafting.
--
-- Registers the `draft-trip-route` service in the premium control plane and adds
-- a reusable route-draft cache. The edge function uses service_role + the
-- existing reserve/complete/release RPCs for atomic quota reservations; clients
-- never read config, usage, reservations, or this cache directly.

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
  'draft-trip-route',
  'openai',
  10,
  true,
  4000,        -- monthly_free_cap: global fresh-call ceiling across all users
  5,           -- default_free_quota: free drafts per user per month
  1209600,     -- cache_ttl_seconds: 14 days for an identical-envelope draft
  true,        -- can_cache_content: route drafts are reusable for the same input
  true,
  false,
  false,
  false,
  null,
  '{"max_tokens":1400,"timeout_ms":30000}'::jsonb
) on conflict (service, provider) do update set
  routing_priority = excluded.routing_priority,
  enabled = excluded.enabled,
  monthly_free_cap = excluded.monthly_free_cap,
  default_free_quota = excluded.default_free_quota,
  cache_ttl_seconds = excluded.cache_ttl_seconds,
  can_cache_content = excluded.can_cache_content,
  config = excluded.config,
  updated_at = now();

-- Reusable cache keyed by a hash of the destination + trip dates + legs
-- envelope. Drafts carry no per-user data, so identical envelopes share a row.
create table if not exists public.trip_route_cache (
  cache_key text primary key,
  provider text not null,
  model text,
  draft jsonb not null,
  fetched_at timestamptz not null default now(),
  expires_at timestamptz not null
);

create index if not exists trip_route_cache_expires_idx
  on public.trip_route_cache (expires_at);

alter table public.trip_route_cache enable row level security;
revoke all on public.trip_route_cache from anon, authenticated;
grant all privileges on public.trip_route_cache to service_role;
