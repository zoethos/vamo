# Trip Map P0 — always-on, progressive journey map

**Why.** Trip Map is **core flow**, not Wave 3 (see `docs/design/NAVIGATION_MAP.md`). It's the live,
fills-as-you-go view of a trip — and the **data spine that consolidates into Trip Wrapped**. The map
shows **always** (empty at trip start, populating live as Visits/expenses/photos land); it is **not**
gated on "enough data." Build the partial/live map now from hooks that already exist.

**Scope = P0.** A trip-scoped Map section: an OSM map that progressively plots placed Visits, expenses
with a place, and geotagged memories, connected into a chronological route, with a day scrubber and an
empty state. **No live per-member trails** (that's P1 — it needs the location-sharing infra from "Follow
me" I-P1) and **no Replay animation** yet.

## A. Positioning (matches the nav map)
- Add `AppRoutes.tripMap(tripId)` and a **"Map" section** on the Trip Dashboard
  (`trip_dashboard_tab.dart`), peer to Plan / Expenses / Balances / Members / Memories — same
  hub-and-spoke pattern as `onPlans`/`onBalances`/`onMembers` (`onMap → AppRoutes.tripMap`).
- New `TripMapScreen` (trip-scoped, `← <destination>` header + share affordance, per the mockup).

## B. Map surface
- **`flutter_map` + OpenStreetMap tiles** (free, no key) + `latlong2`. **Attribution is required** —
  render the OSM attribution on the map. Treat OSM public tiles as a shared, capacity-limited service,
  not an unlimited backend:
  - send an app-identifying User-Agent / supported app identifier, never a library default;
  - honor tile cache headers (or a minimum 7-day local cache if headers are unavailable);
  - do not add offline download, background prefetch, bulk tile warming, or no-cache headers;
  - keep the tile layer behind provider configuration so MapTiler/Stadia/self-hosted tiles can replace
    OSM if beta usage grows.
  **Don't** wire Google/Mapbox in P0 (keys + cost).
- **Always render the map.** Empty state: center on the **geocoded trip destination** (reuse the
  existing geocode path) with a calm overlay "Your journey appears here as you go." Never blank/error.

## C. Moments — progressive markers from existing data
A pure helper `buildTripMapMoments(...)` aggregates trip-scoped points into a typed `MapMoment`
(`{ id, kind, lat, lng, title, at? }`), **skipping anything without coords**:
- **Placed Visits** — `trip_plan_items` kind `visit` with `metadata` lat/lng (from the POI work).
- **Expenses with a place** — `expenses.place_id → places.lat/lng` only. Do **not** treat
  `expenses.captured_lat/lng` as the expense location by default: those fields may be receipt/photo
  capture EXIF, which can be where the image was taken rather than where the purchase happened. If a
  later slice wants to show raw capture coordinates, model them as a separate low-confidence
  "receipt capture" moment with different labeling, not as a place pin.
- **Geotagged memories** — trip photos with EXIF `captured_lat/lng`.
Markers are **type-colored** with the existing `VamoPlanTypeColors` / `AppColors` tokens; tapping a marker
shows a small detail (title + thumbnail for photos). A **chronological route polyline** connects moments
that have a timestamp, in time order.

## D. Day scrubber
- A `Day X of N` control derived from the trip's start/end dates; filtering shows that day's moments +
  route segment. Reuse the trip date logic. "All days" default.

## E. Progressive / live
- The screen watches the trip's plan items / expenses / photos providers, so **markers appear as data
  lands** during the trip (the watch-it-happen feel) — no manual refresh needed.

## F. Tests
- **Dart (pure):** `buildTripMapMoments` — aggregates the three sources, drops coord-less items,
  orders chronologically; the day filter selects the right moments.
- **Widget:** empty state renders (no moments → centered destination + overlay); with moments, markers
  + polyline render; day scrubber filters.

## G. Guardrails / done =
- **Always-on** (never gated on data); graceful when destination won't geocode (world view + empty
  overlay).
- Type colors use the existing `VamoPlanTypeColors` aliases to `AppColors`; do not introduce new raw
  marker hex values. Lime stays CTA-only.
- New deps (`flutter_map`, `latlong2`) added to `feature_split` pubspec; OSM attribution shown.
- OSM compliance verified: app-identifying request headers / app ID, compliant caching, no bulk or
  offline prefetch, no no-cache headers.
- `melos run ci` green; regenerate any new goldens on **Linux**; watch the `AppColors` ratchet.
- No backend/migration change (reads existing data); no prod deploys.

## Notes
- Branch base off `main`; own worktree.
- **P1:** live per-member trails (needs "Follow me" I-P1 location sharing) + the lime "Replay" animation.
- **Powers Wrapped:** the assembled route + moments are Trip Wrapped's data layer — building this *is*
  building Wrapped's spine.
