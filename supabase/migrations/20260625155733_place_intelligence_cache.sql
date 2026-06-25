-- Place intelligence cache.
--
-- User observations are intentionally separate from promoted/global place data:
-- location_observations may carry user_id/trip_id, while every global table
-- below is service-role only and has no user identifier column.

create table if not exists public.location_provider_policies (
  provider text primary key,
  dataset_kind text not null
    check (dataset_kind in ('open_seed', 'live_api', 'derived')),
  can_seed_global boolean not null default false,
  can_store_content boolean not null default false,
  can_store_place_id boolean not null default false,
  can_store_photos boolean not null default false,
  requires_attribution boolean not null default true,
  requires_google_map boolean not null default false,
  max_retention_days integer
    check (max_retention_days is null or max_retention_days >= 0),
  attribution text,
  updated_at timestamptz not null default now(),
  constraint google_places_live_only_policy check (
    provider <> 'google_places_api'
    or (
      dataset_kind = 'live_api'
      and can_seed_global = false
      and can_store_content = false
      and requires_google_map = true
    )
  )
);

comment on table public.location_provider_policies is
  'Provider cache policy guard for place intelligence. Open datasets can seed global cache; live APIs are live-only unless explicitly modeled.';

create table if not exists public.location_canonicals (
  id uuid primary key default extensions.gen_random_uuid(),
  canonical_key text not null unique,
  display_name text not null,
  name_norm text not null,
  feature_type text not null default 'unknown'
    check (
      feature_type in (
        'country',
        'region',
        'locality',
        'neighborhood',
        'poi',
        'landmark',
        'address',
        'unknown'
      )
    ),
  country_code text check (
    country_code is null or country_code ~ '^[A-Z]{2}$'
  ),
  admin1 text,
  latitude double precision check (
    latitude is null or (latitude >= -90 and latitude <= 90)
  ),
  longitude double precision check (
    longitude is null or (longitude >= -180 and longitude <= 180)
  ),
  source_provider text not null references public.location_provider_policies(provider),
  source_place_id text,
  source_rank integer not null default 100 check (source_rank >= 0),
  attribution text not null,
  confidence numeric(5, 4) not null default 0.5000
    check (confidence >= 0 and confidence <= 1),
  promotion_state text not null default 'pending_review'
    check (promotion_state in ('seeded', 'promoted', 'pending_review', 'retired')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint global_canonical_open_seed_guard check (
    promotion_state <> 'seeded'
    or source_provider in ('fsq_os_places', 'geonames', 'wikidata')
  )
);

comment on table public.location_canonicals is
  'Promoted/global canonical places. No user_id/trip_id columns by design.';

create table if not exists public.location_source_refs (
  id uuid primary key default extensions.gen_random_uuid(),
  canonical_id uuid not null references public.location_canonicals(id) on delete cascade,
  provider text not null references public.location_provider_policies(provider),
  source_place_id text not null,
  source_payload_hash text,
  attribution text not null,
  fetched_at timestamptz not null default now(),
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  unique (provider, source_place_id),
  constraint live_api_payload_ttl_required check (
    provider not in ('google_places_api', 'foursquare_places_api')
    or expires_at is not null
  )
);

comment on table public.location_source_refs is
  'Provider references for global places. Live API references require explicit expiry and policy.';

create table if not exists public.location_aliases (
  id uuid primary key default extensions.gen_random_uuid(),
  canonical_id uuid not null references public.location_canonicals(id) on delete cascade,
  alias_norm text not null check (length(alias_norm) between 2 and 160),
  alias_display text,
  scope_country_code text not null default '' check (
    scope_country_code = '' or scope_country_code ~ '^[A-Z]{2}$'
  ),
  scope_admin1 text not null default '',
  scope_feature_type text not null default 'any',
  source_provider text not null default 'user_observation'
    references public.location_provider_policies(provider),
  attribution text not null default 'Vamo user-confirmed observations',
  trusted_source_match boolean not null default false,
  distinct_user_count integer not null default 0 check (distinct_user_count >= 0),
  weight numeric(8, 4) not null default 1.0000 check (weight >= 0),
  confidence numeric(5, 4) not null default 0.5000
    check (confidence >= 0 and confidence <= 1),
  promotion_state text not null default 'pending_review'
    check (promotion_state in ('promoted', 'pending_review', 'retired')),
  promoted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (
    alias_norm,
    scope_country_code,
    scope_admin1,
    scope_feature_type,
    canonical_id
  )
);

comment on table public.location_aliases is
  'Promoted/global aliases. Alias strings are scoped and may point to multiple canonicals for disambiguation.';

create index if not exists location_aliases_lookup_idx
  on public.location_aliases (
    alias_norm,
    scope_country_code,
    scope_feature_type,
    promotion_state,
    weight desc,
    confidence desc
  );

create table if not exists public.location_resolution_cache (
  query_hash text not null,
  scope_country_code text not null default '',
  scope_feature_type text not null default 'any',
  canonical_id uuid not null references public.location_canonicals(id) on delete cascade,
  source_provider text not null references public.location_provider_policies(provider),
  attribution text not null,
  confidence numeric(5, 4) not null default 0.5000
    check (confidence >= 0 and confidence <= 1),
  fetched_at timestamptz not null default now(),
  expires_at timestamptz not null,
  primary key (query_hash, scope_country_code, scope_feature_type)
);

comment on table public.location_resolution_cache is
  'Global query-hash cache for place resolution. Stores hashes only, not raw user queries.';

create index if not exists location_resolution_cache_expires_idx
  on public.location_resolution_cache (expires_at);

create table if not exists public.location_visual_cache (
  id uuid primary key default extensions.gen_random_uuid(),
  canonical_id uuid not null references public.location_canonicals(id) on delete cascade,
  visual_kind text not null
    check (visual_kind in ('provider_photo', 'static_map', 'stored_asset', 'theme')),
  provider text not null references public.location_provider_policies(provider),
  image_url text,
  storage_path text,
  source_place_id text,
  attribution text not null,
  cache_policy text not null default 'ttl'
    check (cache_policy in ('cacheable', 'ttl', 'live_only')),
  fetched_at timestamptz not null default now(),
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  constraint location_visual_has_asset check (
    image_url is not null or storage_path is not null or visual_kind = 'theme'
  ),
  constraint live_visual_ttl_required check (
    cache_policy <> 'ttl' or expires_at is not null
  ),
  constraint google_visual_live_only check (
    provider <> 'google_places_api' or cache_policy = 'live_only'
  )
);

comment on table public.location_visual_cache is
  'Global visual cache for provider-safe place images, static maps, stored assets, or theme fallbacks. No generated fake destination photos.';

create index if not exists location_visual_cache_lookup_idx
  on public.location_visual_cache (canonical_id, visual_kind, fetched_at desc);

create table if not exists public.location_observations (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  trip_id uuid references public.trips(id) on delete set null,
  query_hash text not null,
  query_norm text not null check (length(query_norm) between 2 and 160),
  canonical_id uuid references public.location_canonicals(id) on delete set null,
  resolved_display_name text,
  resolved_feature_type text,
  resolved_country_code text check (
    resolved_country_code is null or resolved_country_code ~ '^[A-Z]{2}$'
  ),
  resolved_latitude double precision check (
    resolved_latitude is null or (resolved_latitude >= -90 and resolved_latitude <= 90)
  ),
  resolved_longitude double precision check (
    resolved_longitude is null or (resolved_longitude >= -180 and resolved_longitude <= 180)
  ),
  provider text references public.location_provider_policies(provider),
  provider_place_id text,
  source_attribution text,
  trusted_source_match boolean not null default false,
  observation_kind text not null default 'typed_destination'
    check (
      observation_kind in (
        'typed_destination',
        'manual_find',
        'create_trip_background',
        'poi_selection',
        'admin_seed'
      )
    ),
  selected boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

comment on table public.location_observations is
  'User-scoped learning events. This is the only place-intelligence table allowed to contain user_id/trip_id.';

create index if not exists location_observations_user_created_idx
  on public.location_observations (user_id, created_at desc);

create index if not exists location_observations_promotion_idx
  on public.location_observations (
    query_norm,
    canonical_id,
    resolved_country_code,
    resolved_feature_type,
    selected,
    trusted_source_match
  )
  where canonical_id is not null;

alter table public.location_provider_policies enable row level security;
alter table public.location_canonicals enable row level security;
alter table public.location_source_refs enable row level security;
alter table public.location_aliases enable row level security;
alter table public.location_resolution_cache enable row level security;
alter table public.location_visual_cache enable row level security;
alter table public.location_observations enable row level security;

revoke all on public.location_provider_policies from anon, authenticated;
revoke all on public.location_canonicals from anon, authenticated;
revoke all on public.location_source_refs from anon, authenticated;
revoke all on public.location_aliases from anon, authenticated;
revoke all on public.location_resolution_cache from anon, authenticated;
revoke all on public.location_visual_cache from anon, authenticated;
revoke all on public.location_observations from anon, authenticated;

grant all privileges on public.location_provider_policies to service_role;
grant all privileges on public.location_canonicals to service_role;
grant all privileges on public.location_source_refs to service_role;
grant all privileges on public.location_aliases to service_role;
grant all privileges on public.location_resolution_cache to service_role;
grant all privileges on public.location_visual_cache to service_role;
grant all privileges on public.location_observations to service_role;

insert into public.location_provider_policies (
  provider,
  dataset_kind,
  can_seed_global,
  can_store_content,
  can_store_place_id,
  can_store_photos,
  requires_attribution,
  requires_google_map,
  max_retention_days,
  attribution
) values
  (
    'fsq_os_places',
    'open_seed',
    true,
    true,
    true,
    true,
    true,
    false,
    null,
    'Foursquare OS Places (Apache-2.0)'
  ),
  (
    'geonames',
    'open_seed',
    true,
    true,
    true,
    false,
    true,
    false,
    null,
    'GeoNames (CC BY 4.0)'
  ),
  (
    'wikidata',
    'open_seed',
    true,
    true,
    true,
    true,
    false,
    false,
    null,
    'Wikidata (CC0)'
  ),
  (
    'foursquare_places_api',
    'live_api',
    false,
    false,
    true,
    false,
    true,
    false,
    30,
    'Foursquare Places API live response'
  ),
  (
    'google_places_api',
    'live_api',
    false,
    false,
    true,
    false,
    true,
    true,
    30,
    'Google Places live response'
  ),
  (
    'static_map',
    'derived',
    false,
    true,
    false,
    true,
    true,
    false,
    30,
    'Static map imagery'
  ),
  (
    'user_observation',
    'derived',
    false,
    false,
    false,
    false,
    false,
    false,
    null,
    'Vamo user-confirmed observations'
  )
on conflict (provider) do update set
  dataset_kind = excluded.dataset_kind,
  can_seed_global = excluded.can_seed_global,
  can_store_content = excluded.can_store_content,
  can_store_place_id = excluded.can_store_place_id,
  can_store_photos = excluded.can_store_photos,
  requires_attribution = excluded.requires_attribution,
  requires_google_map = excluded.requires_google_map,
  max_retention_days = excluded.max_retention_days,
  attribution = excluded.attribution,
  updated_at = now();

create or replace function public.promote_location_aliases(
  p_min_distinct_users integer default 2
) returns integer
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_count integer := 0;
begin
  if p_min_distinct_users is null or p_min_distinct_users < 2 then
    raise exception 'p_min_distinct_users must be >= 2';
  end if;

  with candidates as (
    select
      lower(trim(o.query_norm)) as alias_norm,
      o.canonical_id,
      coalesce(max(o.resolved_country_code), '') as scope_country_code,
      coalesce(max(o.resolved_feature_type), 'any') as scope_feature_type,
      count(distinct o.user_id)::integer as distinct_user_count,
      bool_or(o.trusted_source_match)::boolean as trusted_source_match,
      max(o.source_attribution) filter (where o.source_attribution is not null) as source_attribution,
      max(o.created_at) as last_seen_at
    from public.location_observations o
    where o.selected
      and o.canonical_id is not null
      and length(trim(o.query_norm)) >= 2
    group by lower(trim(o.query_norm)), o.canonical_id
    having bool_or(o.trusted_source_match)
       or count(distinct o.user_id) >= p_min_distinct_users
  ),
  upserted as (
    insert into public.location_aliases (
      canonical_id,
      alias_norm,
      alias_display,
      scope_country_code,
      scope_feature_type,
      source_provider,
      attribution,
      trusted_source_match,
      distinct_user_count,
      weight,
      confidence,
      promotion_state,
      promoted_at,
      updated_at
    )
    select
      c.canonical_id,
      c.alias_norm,
      c.alias_norm,
      c.scope_country_code,
      c.scope_feature_type,
      'user_observation',
      coalesce(c.source_attribution, 'Vamo user-confirmed observations'),
      c.trusted_source_match,
      c.distinct_user_count,
      greatest(1.0, c.distinct_user_count::numeric),
      case
        when c.trusted_source_match then 0.9500
        else least(0.9000, 0.6000 + (c.distinct_user_count::numeric * 0.1000))
      end,
      'promoted',
      now(),
      now()
    from candidates c
    on conflict (
      alias_norm,
      scope_country_code,
      scope_admin1,
      scope_feature_type,
      canonical_id
    ) do update set
      attribution = excluded.attribution,
      trusted_source_match =
        public.location_aliases.trusted_source_match
        or excluded.trusted_source_match,
      distinct_user_count = greatest(
        public.location_aliases.distinct_user_count,
        excluded.distinct_user_count
      ),
      weight = greatest(public.location_aliases.weight, excluded.weight),
      confidence = greatest(
        public.location_aliases.confidence,
        excluded.confidence
      ),
      promotion_state = 'promoted',
      promoted_at = coalesce(public.location_aliases.promoted_at, now()),
      updated_at = now()
    returning 1
  )
  select count(*) into v_count from upserted;

  return v_count;
end;
$$;

revoke all on function public.promote_location_aliases(integer) from public;
grant execute on function public.promote_location_aliases(integer) to service_role;

-- Migration-time PII firewall check for the promoted/global place tables.
do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name in (
        'location_provider_policies',
        'location_canonicals',
        'location_source_refs',
        'location_aliases',
        'location_resolution_cache',
        'location_visual_cache'
      )
      and column_name in ('user_id', 'trip_id', 'profile_id', 'owner_id')
  ) then
    raise exception 'global place-intelligence tables must not contain user-scoped columns';
  end if;
end $$;
