# Plan-Add Redesign — type-first tiles + Visit place-search

**Why.** Realizes the `07-add-to-plan` mockup and **supersedes the nearby direction already on main**.
Add-to-plan becomes **type-first** (6 tiles), and Visit's primary input becomes **place search while
typing** (destination/region search — "Ravello", "a museum in Kyoto"), not a "Discover nearby" button.
The current screen is still a **generic dropdown form** (`plan_item_sheet.dart:162`) with a
coords-anchored **"Discover nearby"** (`discoverNearby` / `visitDiscoverNearby`) — both are replaced.

**Key correction vs. what's on main:** the Visit search is **text search biased to the trip's
destination**, NOT lat/lng "nearby." A user plans Japan from home — there are no local coords. The
`poi-discovery` function today requires `ll=`; it must gain a **destination-search mode**.

## Slice split (so UI isn't blocked on the provider)
- **P0a (pure UI, ships now):** type tiles + per-type fields + **manual place entry** fallback. No
  provider dependency.
- **P0b (provider-gated):** the **live place-search field** wires to the updated `poi-discovery`. Manual
  path is the bridge until the search mode + key are ready.

## A. Type-first tiles (replaces the dropdown)
- Replace the `PlanItemKind` dropdown with a 2×3 **tile grid**: Visit · Train · Flight · Transfer ·
  Lodging · Other. One tap selects the type, themes the sheet, and **swaps the form live** (per-type).
- **Activity:** not a tile. `PlanItemKind.activity` stays valid (existing items + RSVP capability keep
  working); new items use Visit/Other. Confirm with product before orphaning the RSVP path — do not
  remove `activity` handling.

## B. Per-type smart forms
- **Visit (P0):** a **place-search field** (see C) with live suggestions; pick → auto-fills title +
  address + lat/lng + place_id into `metadata`. **Remove "Find coordinates"** from the UI.
- **P1 (follow-up):** Train/Flight → from→to; Transfer → mode (the S53 `metadata.subtype`); Lodging →
  check-in/out. **Times optional, never a gate.** For P0, keep current fields for non-Visit types.

## C. Visit place-search (P0b) — search-first, region-biased
- Client: a debounced search field (≈300ms, ≥3 chars). On query, call `poi-discovery` in **search
  mode**, biased to the **trip destination** (so it works before the Visit has coords). Show suggestion
  rows (name · category · locality/distance). Tap → auto-fill; nothing requires the user to type an
  address.
- **`poi-discovery` change:** add a **search mode** — accept `{ trip_id, query, regionBias? }` and either
  pass Foursquare `near=<trip destination text>` **or** geocode the trip destination → `ll`, instead of
  requiring caller-supplied `lat,lng`. Keep `nearby(lat,lng)` as the secondary mode.
- **Metering (autocomplete cost):** debounce + **provider session tokens** (Google bills Autocomplete
  *per session*, one Details on selection). **Meter per resolved-place / search session, NOT per
  keystroke** — update the control-plane so the freemium quota counts committed selections, not typing.
- Provider-agnostic `Poi` + category buckets stay; keys server-side; cache by (region/geohash, category,
  query) per the control plane.

## D. Pinned CTA
- One **lime** pinned CTA reflecting the required sequence: disabled "tap a type" → "tap a place" →
  enabled "Add". Single lime primary per screen (don't reintroduce decorative lime).

## E. Manual fallback (mandatory)
- If search returns nothing / the provider is down / over quota → the user can still **type a place name
  + optional address and save** (geocode silently if possible, else save text-only). The add must never
  be blocked by the POI layer.

## F. Tests / guardrails
- **Dart:** tile selection swaps the form + themes; Visit search debounces + maps results → metadata;
  manual fallback saves without provider; CTA enable sequence (type→place).
- **Edge:** `poi-discovery` search mode (query + region bias, no caller coords); per-session metering;
  gated → upsell (unchanged).
- `melos run ci` green; goldens on **Linux** (the sheet changes a golden surface); watch the `AppColors`
  ratchet; deploy fn + migrations to **staging** (not prod) + `rls_smoke`.
- "POI resolution feeds Trip Map" is free downstream — a placed Visit already carries lat/lng.

## Notes
- Branch base off `main`; own worktree. Replaces the `discoverNearby` UI + dropdown; updates the
  `poi-discovery` function and the D-P1 spec's "nearby" framing to "search-first."
