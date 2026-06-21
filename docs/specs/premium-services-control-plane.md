# Premium services control plane (the freemium "mantra")

_Drafted 2026-06-21. The reusable pattern for every paid/external dependency: POI, weather, FX, the
Wave-4 LLM extractor, and anything future._

## The mantra
Every premium/external service is consumed through the **same shape**:
**gateway → cache → per-user meter → multi-provider free-tier routing → upsell-on-limit.**
Stay on providers' **free layers**; when a user's consumption would exceed free capacity, **notify them
to upgrade** (Vamo Plus) rather than silently paying. POI is the first instance; weather + FX adopt it.

## The economic reality this is built around
Provider free tiers are **global monthly pools, not per-user.** (Foursquare Pro currently has a small
whole-app free monthly pool; Google Places pricing/terms are separate and must be checked before it is
enabled.) Three consequences shape the design:

1. **Ration the global pool into per-user quotas.** The upsell fires when a *user* exceeds their
   *per-user* quota; the quotas must sum within the global free pool or Vamo starts paying.
2. **Caching is the lever, but provider policy decides what can be cached.** A geohash+category cache
   means most lookups for popular destinations hit cache (free, unmetered), so the global free pool
   serves far more users. **Foursquare is the free-tier default because it is the cache-friendly POI
   provider.** Google Places is not a generic cache source: it can be used later as a live resolver /
   visualization provider, with provider-specific retention, attribution, map-use, and no-photo-storage
   rules.
3. **Plus must cover marginal cost.** A Plus user's overflow is what Vamo actually pays the provider
   for — so Vamo Plus pricing must cover a heavy user's marginal provider cost + margin.

## Routing & metering model
- **Free user:** a small monthly quota of *fresh* (uncached) premium lookups per service. Cache hits are
  free + unmetered. Crossing the quota → gated result → upsell notification.
- **Plus user:** higher/unlimited quota; overflow is paid by Vamo, funded by the subscription.
- **Global guard / fallover:** per-provider monthly free caps; route **Foursquare → (future Google live
  resolver or paid provider) → gate** as each free pool exhausts, app-wide. Admin sees usage vs caps and
  can switch/flip. Do not enable a provider in routing until its policy flags are modeled.
- **Tunable, not hard-coded:** per-user quota, per-provider free cap, and routing order are all
  **config rows** — tune without a deploy or app release.

## Components
- **`provider_config`** — per service (`poi`, `weather`, `fx`, `llm`): `routing_order[]`, per-provider
  `monthly_free_cap`, `enabled`, `default_free_quota`, plus provider policy flags
  (`cache_ttl_seconds`, `can_cache_content`, `can_cache_place_id`, `can_store_photos`,
  `requires_attribution`, `requires_google_map`, `max_retention_days`). Read (cached) by the gateways at
  runtime.
- **`service_usage`** — counters: per-provider **monthly global** + per-user **monthly**, per service.
  Drives routing decisions, quota checks, and the dashboard.
- **`entitlements`** — per user: `plan` (`free`|`plus`), optional quota overrides.
- **`service_usage_reservations`** — idempotent reservations for fresh provider calls. Gateways reserve
  capacity in Postgres before calling the provider, then mark `completed` / `failed` after the adapter
  returns. This prevents parallel requests from overspending the user quota or global provider cap.
- **Gateway edge functions** (`poi-discovery`, `weather-forecast`, `fx-rates`, future `llm-*`) all run the
  same flow:
  ```
  auth(user) → cache lookup
    ├─ hit → return (unmetered)
    └─ miss →
        pick provider = first enabled provider whose policy allows this use
        reserve user + global quota atomically
          ├─ over quota/cap → return { gated: true, upsell: <service> }
          └─ ok → call provider adapter → normalize → meter completion → cache if policy allows → return
  ```
- **Provider adapters** behind one interface per service (e.g. `foursquareAdapter` / `googleAdapter`),
  each normalizing to a Vamo model + category buckets (provider taxonomy hidden — same idea as weather
  condition buckets).
- **Admin dashboard** (`web/apps/site`, `is_admin` only): switch provider / routing order, set caps +
  default quotas, watch global + cohort usage vs caps, kill switch — per service. RLS locks the config +
  usage tables to admin/service-role.
- **Upsell**: when a user crosses a quota, a record-first notification (S46 pipeline) → deep-link to Vamo
  Plus, contextual to the service they hit.

## Why "wrap", never direct
Provider APIs aren't standardized (different shapes, categories, auth) and have different caching
licenses. Direct client use would make switching require an app release, leak keys, block caching/cost
control, and couple the UI to a provider taxonomy. The normalized gateway + adapters + buckets is
**mandatory** for switchability, metering, and key safety. This is the established Vamo pattern
(`fx-rates`, `weather-forecast`).

## Privacy / safety
Keys server-side only; send providers the minimum (coords, not user identity beyond the metering key);
cache per the provider's license; no PII to providers; the gate is graceful (never breaks the app —
shows the upsell).

## Provider content ownership
Provider content is not Vamo content. The durable Vamo record is the user's trip/visit plus Vamo-owned
media. For Google Places specifically:

- Store the provider place id long-term when allowed (`google_place_id` / equivalent).
- Use Google place details/photos as live visualization only, with required attribution and map/content
  rules.
- Do **not** copy Google photo bytes into Supabase Storage.
- Do **not** build a reusable cross-user Google POI/photo cache.
- Let users add their own on-site photos/videos/notes and attach those Vamo-owned media items to the
  visit/place id.

## Sequencing
1. **Build the shared control plane** (`provider_config` / `service_usage` / `entitlements` /
   `service_usage_reservations` + the gateway middleware) with **POI/Foursquare as the first consumer**
   (see `docs/slices/D_P1_A_POI_DISCOVERY_PROMPT.md`).
2. **Admin dashboard** to administer it centrally + evaluate a real Google live-resolver adapter only
   after its policy flags, attribution, and map/content constraints are implemented.
3. **Retrofit weather + FX** onto the same plane; **Wave-4 LLM** is born on it.

## Open decisions
1. Per-user free quota per service: seed POI at **5 fresh Foursquare lookups/user/month**.
2. Provider cap + safety margin: seed Foursquare at **8,000 fresh calls/month** until production burn-down
   data proves a higher cap is safe.
3. Cache TTL + key granularity per service: seed POI at **geohash precision 6 × category × 7 days** for
   Foursquare content only.
4. Vamo Plus price point vs. modeled heavy-user marginal cost.
5. Gate UX: **soft gate** first (manual + "from this trip" places still work; premium discovery shows an
   upsell row).
6. Usage counter store: **Postgres first** (`service_usage` + reservations RPC), not KV/Redis, so quota
   checks are transactional and auditable.
