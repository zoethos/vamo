# D-P1.a — POI discovery (first consumer of the premium control plane)

**Why.** Completes D (Visit/POI): real **nearby-POI discovery** for a Visit, the piece deferred from
S51. Built as the **first consumer of the premium services control plane**
(`docs/specs/premium-services-control-plane.md`) — so it ships the metering/routing/upsell pattern that
weather, FX, and the Wave-4 LLM will reuse.

**Scope = P0.** Foursquare-first discovery behind the gateway, with caching, per-user metering, the
Foursquare→Google routing seam (Google adapter may be stubbed this slice), and the upsell-on-limit gate.
Provider/quotas are **config rows** (admin UI is the next slice). Stay on free tiers.

## A. Control-plane foundation (shared — build here, reused later)
- Tables: `provider_config` (seed `poi`: `routing_order=['foursquare','google']`, per-provider
  `monthly_free_cap`, `enabled=true`, `default_free_quota`), `service_usage` (per-provider monthly +
  per-user monthly counters), `entitlements` (per user `plan` default `free`). RLS: config + usage are
  **service-role/admin only**; clients never read them directly.
- Gateway middleware (Deno, shared `_shared/premium.ts`): `auth → cache → routing(provider by free cap)
  → quota check → call → meter → cache`, returning `{ gated, upsell }` when a user is over quota.

## B. `poi-discovery` edge function
- Input `{ lat, lng, category?, radius? }` (user JWT). Output: normalized `Poi[]` or
  `{ gated: true, upsell: 'poi' }`.
- **Normalized model + category buckets** (provider-agnostic): `Poi { id, name, category, lat, lng,
  address?, rating?, distanceM, source }`, `PoiCategory ∈ {food, lodging, attraction, museum, nature,
  nightlife, shopping, transport, other}`. Adapters map provider categories → buckets server-side.
- **`foursquareAdapter`** (real) + **`googleAdapter`** (interface; may stub). Keys in function secrets
  (`FOURSQUARE_API_KEY`, later `GOOGLE_PLACES_API_KEY`) — **no client key**.
- **Cache** `poi_cache` keyed by `(geohash(lat,lng,~precision 6), category, provider)` + TTL; cache hits
  are unmetered. Respect provider caching license (Foursquare cacheable; Google minimal).

## C. Client (Visit add-flow)
- In `_VisitDetailsSection` (behind `suggestsPois`), add a **"Discover nearby"** section: using the
  Visit's place coords (or the trip destination, geocoded), call `poi-discovery` → show POI cards
  (bucket icon + name + distance + category); one-tap fills the Visit `metadata` (place_label, address,
  lat/lng, place_id). Keep the existing **manual** + **"from this trip"** paths.
- **Gate UX:** if the response is `gated`, hide the discovery list and show a single, calm upsell row
  ("You've used your free place lookups this month — Vamo Plus for more") → deep-link to Plus. Never an
  error; the manual + trip-places paths still work.

## D. Upsell notification
- When the gateway first returns `gated` for a user in a period, enqueue a record-first notification
  (S46 pipeline) → deep-link to Vamo Plus, contextual to POI. Debounce (once per period).

## E. Tests
- **Dart:** `Poi`/`PoiCategory` parse incl. unknown→`other`; `gated` response → upsell row (no error);
  discovery card tap fills Visit metadata.
- **Edge:** Foursquare adapter normalization (categories→buckets); cache hit path is unmetered; quota
  exceeded → `{ gated }`; routing picks the next provider when the first's free cap is exhausted.
- **rls_smoke:** a member can call `poi-discovery`; `provider_config`/`service_usage`/`poi_cache` are
  **not** client-readable; metering increments per user.

## F. Guardrails / done =
- Stay on free tiers: per-provider `monthly_free_cap` + per-user `default_free_quota` enforced; over →
  upsell, not silent spend.
- Provider + quotas are **config rows** (switchable without deploy); app is provider-agnostic (buckets).
- Keys server-side; graceful gating; cache respects each provider's license; minimum data to providers.
- New edge fn + migrations to **staging** (`sfwziwcuyctxvidivnsh`, not prod) + `rls_smoke` green;
  `melos run ci` green; goldens on **Linux** if the Visit surface changes; watch the `AppColors` ratchet.
- **Greenlight before build:** Foursquare account + key, and the first numbers (per-user free quota,
  Foursquare monthly free cap, cache TTL).

## Notes
- Branch base off `main`; own worktree.
- Next slices: **D-P1.b** central admin dashboard (`web/apps/site`, `is_admin`) + real Google adapter;
  then retrofit weather + FX onto the same control plane.
