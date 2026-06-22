# Wave 4 — Transport Resolver, Phase 1 (MVP) — implementation prompt

Spec: [`docs/specs/wave4-transport-resolver.md`](../specs/wave4-transport-resolver.md).
Providers: [`docs/specs/wave4-transport-resolver-providers.xlsx`](../specs/wave4-transport-resolver-providers.xlsx).
New branch off latest `main`, own worktree.

**Goal of Phase 1:** the full loop on the cheapest solid sources, single provider per mode, Free tier only —
**resolve a connection → pick one → insert it into the trip plan as a Transfer item.** No premium providers,
no entitlement gating yet (that's Phase 3).

This is the **second consumer of the premium-services control plane** (after POI/Foursquare) and reuses the
existing **Transfer** plan item. Do **not** invent new plan schema.

## Build
1. **`transport` service in the control plane.** Add `provider_config` / `service_usage` rows for
   `service = 'transport'` (providers `navitia`, `aerodatabox`) with `routing_order`, `monthly_free_cap`,
   `default_free_quota`, `enabled`. No new tables — reuse the POI control-plane tables/RPCs.
2. **Edge function `transport-resolve`** (clone the `poi-discovery` structure): input
   `{ trip_id, mode, origin, destination, date, session_id }`; tier/mode → provider via `routing_order`;
   **reserve → call adapter → normalize → complete/release**; per-session metering (idempotency by
   `session_id`); cache; `{ gated, upsell: 'transport' }` on quota. Secrets server-side. Adapters: **Navitia**
   (train/bus, EU+US) and **AeroDataBox** (plane); normalize both into one model:
   ```
   TransportOption { mode, operator, serviceRef, origin, destination, departAt, arriveAt, legs[], source }
   ```
3. **Client view `TransportResolverScreen`** (mirror the POI/visit search UX):
   - Inputs: origin + destination (reuse places search/geocode), date (clamp to `TripPlanDateBounds`),
     mode = `TransferSubtype` (train/bus/plane).
   - Debounced call to `transport-resolve` (per-session id, like the visit search), loading/empty/gated/error
     states.
   - Results = ranked connection rows (depart → arrive · operator · duration · changes). **Single-select pick.**
   - On pick → build `TransferMetadata` (`subtype`, `origin`, `destination`, `provider`, `reference = serviceRef`,
     additive `depart_at`/`arrive_at`/`operator`) → `addPlanItem` (kind `transfer`). Times land inside trip bounds.
   - Entry: from **Add-to-Plan → Transfer** ("Find a connection") + a Plan-tab action. Route
     `AppRoutes.tripTransportResolve(tripId)`.
4. **Additive metadata** `depart_at` / `arrive_at` / `operator` via the existing S49 object-preserving
   encode/parse (older clients ignore them).

## Guardrails / done
- **Resolution only** — no booking/PNR/ticketing. No keys in the client (all provider calls in the edge fn).
- **Mock providers in tests** — never hit real Navitia/AeroDataBox in CI (the Foursquare lesson).
- Brand tokens (`context.vamoColors` / `AppColors`), lime CTA-only, watch the AppColors ratchet.
- Tests: pure normalizer per provider fixture; tier→provider selection; `TransferMetadata` round-trip
  (incl. additive keys); widget results+pick+empty-fallback.
- `melos run ci` green; goldens on Linux. No plan-schema migration; only `transport` control-plane config rows.
- Branch off `main`, own worktree; no prod deploys, no `main` commits.

## Deferred to Phase 2/3 (do NOT build now)
- Raw-GTFS gap adapters (Mobility DB / gtfs.de / SNCF), Aviationstack, server schedule cache (Phase 2).
- Distribusion / ViaggiaTreno / OAG / Cirium, entitlement gating + upsell, admin provider switch, `pro`
  tier (Phase 3).
