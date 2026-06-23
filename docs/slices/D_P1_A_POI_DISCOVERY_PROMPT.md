# D-P1.a — POI discovery (first consumer of the premium control plane)

**Why.** Completes D (Visit/POI): real **nearby-POI discovery** for a Visit, the piece deferred from
S51. Built as the **first consumer of the premium services control plane**
(`docs/specs/premium-services-control-plane.md`) — so it ships the metering/routing/upsell pattern that
weather, FX, and the Wave-4 LLM will reuse.

**Scope = P0.** Foursquare-only real discovery behind the gateway, with caching, per-user metering,
atomic global-cap reservation, the Google routing/policy seam stubbed for later, and the
upsell-on-limit gate. Provider/quotas are **config rows** (admin UI is the next slice). Stay on free
tiers.

Use the **current Foursquare Places API only**. Do not use legacy V3 endpoints.

## A. Control-plane foundation (shared — build here, reused later)
- Tables:
  - `provider_config` (seed `poi`: `routing_order=['foursquare']`, Foursquare
    `monthly_free_cap=500`, `enabled=true`, `default_free_quota=5`,
    `cache_ttl_seconds=604800`, `can_cache_content=true`, `can_store_photos=false`).
  - `service_usage` (per-provider monthly + per-user monthly counters).
  - `service_usage_reservations` (idempotent fresh-call reservations; unique idempotency key; status
    `reserved|completed|failed|released`).
  - `entitlements` (per user `plan` default `free`).
  RLS: config + usage are **service-role/admin only**; clients never read them directly.
- Gateway middleware (Deno, shared `_shared/premium.ts`): `auth → cache → route provider by policy/cap
  → reserve quota atomically → call → meter completion → cache if policy allows`, returning
  `{ gated, upsell }` when a user is over quota or the app-wide cap is exhausted.
- Reservation must be transactional in Postgres (RPC preferred) so parallel requests cannot overspend
  the per-user quota or the global provider cap.

## B. `poi-discovery` edge function
- Input `{ lat, lng, category?, radius? }` (user JWT). Output: normalized `Poi[]` or
  `{ gated: true, upsell: 'poi' }`.
- **Normalized model + category buckets** (provider-agnostic): `Poi { id, name, category, lat, lng,
  address?, distanceM, source, providerPlaceId }`, `PoiCategory ∈ {food, lodging, attraction, museum,
  nature, nightlife, shopping, transport, other}`. Adapters map provider categories → buckets
  server-side.
- P0 fields are intentionally basic: **no provider photos, ratings, tips, reviews, opening hours, rich
  amenities, or premium fields**.
- **`foursquareAdapter`** (real) + **`googleAdapter`** (interface/policy stub only). Keys in function
  secrets (`FOURSQUARE_API_KEY`, later `GOOGLE_PLACES_API_KEY`) — **no client key**.
- **Cache** `poi_cache` keyed by `(geohash(lat,lng,precision 6), category, provider)` + Foursquare TTL
  7 days; cache hits are unmetered. The cache layer must be provider-policy aware. Google content must
  not enter this reusable cache unless a later slice explicitly implements the allowed retention,
  attribution, and map/content rules.

## C. Client (Visit add-flow)
- In `_VisitDetailsSection` (behind `suggestsPois`), add a **"Discover nearby"** section: using the
  Visit's place coords (or the trip destination, geocoded), call `poi-discovery` → show POI cards
  (bucket icon + name + distance + category); one-tap fills the Visit `metadata` (place_label, address,
  lat/lng, place_id). Keep the existing **manual** + **"from this trip"** paths.
- **Gate UX:** if the response is `gated`, hide the discovery list and show a single, calm upsell row
  ("You've used your free place lookups this month — Vamo Plus for more") → deep-link to Plus. Never an
  error; the manual + trip-places paths still work.
- **Media rule:** provider imagery is not saved. Users can attach their own on-site Vamo photos/videos
  to the Visit. If a Google provider id is added later, Vamo media may be mapped to that id, but Google
  photo bytes/photo names are never copied into Vamo storage.

## D. Upsell notification
- When the gateway first returns `gated` for a user in a period, enqueue a record-first notification
  (S46 pipeline) → deep-link to Vamo Plus, contextual to POI.
- Add a unique debounce guard such as `(user_id, service, period_month, reason)` so repeated gated
  responses cannot spam notifications.

## E. Tests
- **Dart:** `Poi`/`PoiCategory` parse incl. unknown→`other`; `gated` response → upsell row (no error);
  discovery card tap fills Visit metadata.
- **Edge:** Foursquare adapter normalization (categories→buckets); cache hit path is unmetered; quota
  exceeded → `{ gated }`; global cap exhausted → `{ gated }`; reservation RPC prevents concurrent
  overspend; Google stub is never selected in P0.
- **rls_smoke:** a member can call `poi-discovery`; `provider_config`/`service_usage`/`poi_cache` are
  **not** client-readable; metering increments per user; reservation rows are not client-readable.

## F. Guardrails / done =
- Stay on free tiers: per-provider `monthly_free_cap` + per-user `default_free_quota` enforced; over →
  upsell, not silent spend.
- Provider + quotas are **config rows** (switchable without deploy); app is provider-agnostic (buckets).
- Keys server-side; graceful gating; cache respects each provider's license; minimum data to providers.
- No provider photos/ratings/rich fields in P0; no Google content caching; user media only.
- New edge fn + migrations to **staging** (`sfwziwcuyctxvidivnsh`, not prod) + `rls_smoke` green;
  `melos run ci` green; goldens on **Linux** if the Visit surface changes; watch the `AppColors` ratchet.
- **Greenlight before build:** Foursquare account + key. Seed numbers are locked for P0:
  per-user free quota `5` fresh lookups/month, Foursquare cap `500` fresh calls/month, cache TTL `7`
  days, geohash precision `6`. Raise the provider cap only after checking current Foursquare billing.

## Notes
- Branch base off `main`; own worktree.
- Next slices: **D-P1.b** central admin dashboard (`web/apps/site`, `is_admin`) + provider policy editor;
  **D-P1.c** optional Google live resolver only after attribution/map/cache constraints are implemented;
  then retrofit weather + FX onto the same control plane.
