# POI place info card

## Goal

When a Visit place is resolved from POI search, Vamo should also surface useful
place information inside the Plan flow without making extra paid provider calls
per keystroke.

## Phase 1 - ship now

- Widen the existing Foursquare Places search fields on the same metered
  `poi-discovery` call.
- Normalize optional place info into the existing provider-neutral POI payload:
  photo, description, website, phone, hours, rating, and price.
- Carry those fields through `PoiSummary` and snapshot them into Visit metadata
  when the user selects a POI.
- Add a shared `PlaceInfoCard` bottom sheet.
- Extend `VamoSlidableRow` with an optional Info action.
- Use right-to-left swipe on Add-to-Plan POI suggestion rows to open the info
  card. Long-press keeps the accessible action-menu fallback.

## Constraints

- No new provider call on typing beyond the existing debounced search.
- No live provider smoke in CI or RLS gates.
- Manual Visit save must keep working when the provider is unavailable or gated.
- Lime remains reserved for primary save/add CTAs. Info uses the secondary theme
  action color.
- AppColors ratchet must not be raised.

## Later

- Phase 2: reuse `PlaceInfoCard` on saved Visit timeline rows and Trip Map
  marker sheets from the Visit metadata snapshot.
- Phase 3: add a `placeinfo` enrichment gateway for free Wikipedia/Wikivoyage or
  OpenTripMap summaries, with optional LLM traveler notes behind the existing
  metered control-plane pattern.
