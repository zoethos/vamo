# Premium services control plane (the freemium "mantra")

_Drafted 2026-06-21. The reusable pattern for every paid/external dependency: POI, weather, FX, the
Wave-4 LLM extractor, and anything future._

## The mantra
Every premium/external service is consumed through the **same shape**:
**gateway → cache → per-user meter → multi-provider free-tier routing → upsell-on-limit.**
Stay on providers' **free layers**; when a user's consumption would exceed free capacity, **notify them
to upgrade** (Vamo Plus) rather than silently paying. POI is the first instance; weather + FX adopt it.

## The economic reality this is built around
Provider free tiers are **global monthly pools, not per-user.** (Foursquare's free tier is ~N calls/mo
for the whole app; same for Google.) Three consequences shape the design:

1. **Ration the global pool into per-user quotas.** The upsell fires when a *user* exceeds their
   *per-user* quota; the quotas must sum within the global free pool or Vamo starts paying.
2. **Caching is the lever.** A geohash+category cache means most lookups for popular destinations hit
   cache (free, unmetered), so the global free pool serves far more users. **Foursquare is the free-tier
   default because its license permits caching**; Google's caching limits make its pool stretch less —
   so Google is the *second* routing hop, not the first.
3. **Plus must cover marginal cost.** A Plus user's overflow is what Vamo actually pays the provider
   for — so Vamo Plus pricing must cover a heavy user's marginal provider cost + margin.

## Routing & metering model
- **Free user:** a small monthly quota of *fresh* (uncached) premium lookups per service. Cache hits are
  free + unmetered. Crossing the quota → gated result → upsell notification.
- **Plus user:** higher/unlimited quota; overflow is paid by Vamo, funded by the subscription.
- **Global guard / fallover:** per-provider monthly free caps; route **Foursquare → Google → (paid or
  gate)** as each free pool exhausts, app-wide. Admin sees usage vs caps and can switch/flip.
- **Tunable, not hard-coded:** per-user quota, per-provider free cap, and routing order are all
  **config rows** — tune without a deploy or app release.

## Components
- **`provider_config`** — per service (`poi`, `weather`, `fx`, `llm`): `routing_order[]`, per-provider
  `monthly_free_cap`, `enabled`, `default_free_quota`. Read (cached) by the gateways at runtime.
- **`service_usage`** — counters: per-provider **monthly global** + per-user **monthly**, per service.
  Drives routing decisions, quota checks, and the dashboard.
- **`entitlements`** — per user: `plan` (`free`|`plus`), optional quota overrides.
- **Gateway edge functions** (`poi-discovery`, `weather-forecast`, `fx-rates`, future `llm-*`) all run the
  same flow:
  ```
  auth(user) → cache lookup
    ├─ hit → return (unmetered)
    └─ miss →
        pick provider = first in routing_order whose global free cap not exhausted
        check user monthly quota (by entitlement)
          ├─ over quota → return { gated: true, upsell: <service> }
          └─ ok → call provider adapter → normalize → meter (global + user) → cache → return
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

## Sequencing
1. **Build the shared control plane** (`provider_config` / `service_usage` / `entitlements` + the gateway
   middleware) with **POI as the first consumer** (see `docs/slices/D_P1_A_POI_DISCOVERY_PROMPT.md`).
2. **Admin dashboard** to administer it centrally + add the Google adapter so the switch is real.
3. **Retrofit weather + FX** onto the same plane; **Wave-4 LLM** is born on it.

## Open decisions
1. Per-user free quota per service (start small — e.g. POI: ~N fresh lookups/mo) — pick the first numbers.
2. Cache TTL + key granularity per service (geohash precision × category for POI).
3. Vamo Plus price point vs. modeled heavy-user marginal cost.
4. Gate UX: hard block + upsell, or soft (degrade to "from this trip" places only) + upsell.
5. Usage counter store: a Postgres `service_usage` table (simple, transactional) vs. a KV/Redis (faster,
   another dependency) — recommend Postgres first.
