# S51 — Visit plan-item + POI surfacing (Horizon D · C-light's first consumer)

**Why.** C-light (S49) shipped the capability spine (`plan_item_capabilities`, `trip_plan_items.metadata`)
but no consumer. **Visit** is the first one: a place-bearing plan item that turns "we want to go
somewhere" into a structured, timeline-able item, and lets a trip's already-resolved places (from
receipts/photos) be added to the plan in one tap. It also proves the enum-extension path that every
later kind (Transfer, Stay, Meal, Guided Tour) will reuse.

**Scope = P0 (ships zero new external dependency):**
- **Visit** as a first-class `plan_item_kind`.
- Place-bearing metadata entered manually + geocoded via the **existing** `geocodeAddress`
  (OS geocoding, no key), **or** added one-tap from the trip's existing `places` rows.
- Capability-gated surfacing via the data-driven `suggests_pois` flag (already `true` for `activity`;
  set `true` for `visit`).

**Explicitly P1 / deferred:** external POI **discovery** (nearby search via Google Places / Foursquare /
OSM). `places` is capture-derived (receipt/EXIF), NOT a discovery catalog, and geocoding is
address→coords only. A discovery provider is a key/cost/attribution commitment (the roadmap's open
question) and must NOT enter P0. It lights up later behind `suggests_pois` with no schema churn.

## A. Schema — TWO migrations (native enum gotcha)
`plan_item_kind` is a Postgres enum ([0016](../../supabase/migrations/0016_trip_plan_items.sql)); S49's
header mandates a standalone `ALTER TYPE … ADD VALUE` before any use.
- **Migration A** `…_s51_plan_kind_visit.sql` (standalone, nothing else):
  `alter type plan_item_kind add value if not exists 'visit';`
  A new enum value cannot be used in the same transaction that adds it — keep this file isolated.
- **Migration B** `…_s51_visit_capabilities.sql` (separate, later timestamp):
  `insert into plan_item_capabilities (kind, …) values ('visit', wave_min 2, suggests_pois true,
  has_details_form true, rest false) on conflict (kind) do update …`.
  Document the Visit metadata shape (object, per the S49 `jsonb_typeof = 'object'` check):
  `{ place_label: string, address?: string, lat?: number, lng?: number, place_id?: uuid }`.
- **No new tables.** Visit place data lives in `trip_plan_items.metadata`; `metadata.place_id`
  optionally references an existing `places.id`.

## B. Client
- `PlanItemKind.visit` in [plan_models.dart](../../packages/feature_split/lib/src/plan/plan_models.dart):
  add enum value, an icon (`Icons.place_outlined`), keep `parse` fallback to `other`, and
  `fallbackFor(visit)` → `supportsRsvp:false, suggestsPois:true, hasDetailsForm:true`.
- `plan_item_sheet`: when kind == visit, reveal place fields (label **required**; address optional →
  geocode on blur via `geocodeAddress`, store lat/lng). Persist to `metadata` via `encodePlanMetadata`.
- **POI surfacing (P0):** in the Visit add-flow, show a "From this trip" strip listing existing
  `places` rows (label/address); tapping one creates a Visit plan item with that place in metadata
  (and `metadata.place_id`). Gate the strip on `capabilitiesFor(visit).suggestsPois`.

## C. Places read path
- Reuse `places` — add a trip-scoped read (`id,label,address,lat,lng,source,confidence where trip_id`)
  in the places/plan repository; RLS is already member-scoped (`places_all`). Do NOT duplicate the
  place model — reuse `PlaceSummary`.

## D. Models / Drift / sync
- `metadata` is already threaded through `planItemUpsert` (S49) — **no `schemaVersion` bump**. Confirm
  Visit metadata round-trips on create, edit, and reorder/partial upsert (don't drop `metadata`).
- `kind` flows as `kind.name` → the enum value `'visit'`; no new write RPC — Visit uses the existing
  plan-item write path.

## E. Tests
- **Dart:** `PlanItemKind.parse('visit')`; `fallbackFor(visit)` flags; metadata encode/decode for a
  Visit place (object preserved, unknown keys kept); places→Visit-candidate mapping.
- **rls_smoke:** a member can insert a `kind='visit'` plan item (enum value live); metadata persists;
  `plan_item_capabilities` has a `visit` row with `suggests_pois = true`; an outsider cannot read the
  trip's `places` or plan items.
- If the plan sheet changes a golden surface, **regenerate goldens on Linux**; watch the `AppColors`
  ratchet (`tool/appcolors_baseline.txt`, currently 162) — bump only for legitimately new refs.

## F. Guardrails / done =
- Two-migration enum split (ADD VALUE standalone, seed/use separate). Apply to a **non-prod** Supabase,
  then `dart run tool/rls_smoke.dart` green incl. the Visit-create + capability + places-read cases;
  `melos run ci` green.
- P0 requires **no external provider/key**. External POI discovery is P1, decided then, behind
  `suggests_pois` (no schema churn).
- Visit metadata stays a JSON object; unknown keys preserved (S49 invariant).
- **Legacy kinds untouched** — `visit` is purely additive; no `flight/train/lodging` reconciliation
  here (that decision belongs to **S53 Transfers**, where the overlap actually bites).

## Notes
- **Branch base:** `feature/s51-visit-poi` off `main` after `f7c1e0ae`.
- This is the template for the rest of C's taxonomy: each new kind = one standalone `ALTER TYPE ADD
  VALUE` migration + a capability seed + Dart enum + type-aware fields. Keep it boring and repeatable.
- **Next:** S52 = external POI discovery (provider decision) if pursued; **S53 = Transfers (E)** —
  `transfer` kind + `metadata.subtype` (car_rental/train/transit/drive/flight), legacy flight/train
  reconciliation decided there.
