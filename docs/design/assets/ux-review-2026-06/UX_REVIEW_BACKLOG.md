# UX/UI Review Backlog — 2026-06

Source: Design review (Claude) / 2026-06-21 / mockups: `Vamo UX Improvements.dc.html` (standalone in repo) · screenshots in this folder
Status: raw review, not yet triaged

Scope: full pass over every built view plus spec/roadmap surfaces not yet implemented. Mockups in the locked brand tokens; "Proposed" frames are interactive. Numbered references (①②③) map to the lime markers in each mockup.

This pass adds two newly-mocked screens since the prior set: **Profile** (06) and **Add to Plan** (07).

---

## High Priority

### H1 — Restore the 5-slot nav + context-aware goLime FAB
**Screens:** Main shell · `01-navigation-fab.png`
Shipped shell is 4-slot (Trips · Activity · Expenses · Profile) with no center FAB; brief + both brand boards specify a 5-slot nav with a center lime "+". Logging an expense has no global entry (~3–4 taps today), and goLime is absent from live flows. ① Add the docked lime FAB (one tap from anywhere). ② Context-aware: "+expense" on Expenses, "+trip" elsewhere; retire the app-bar "+". ③ Brings the action color into the core loop.

### H2 — Lighten Add Expense; make split editable; pin the CTA
**Screens:** Add Expense · `02-add-expense.png`
Long single-column form (9 fields); spec flags `flow_abandoned`. Split field is read-only; Save scrolls away. ① Amount-first keypad; currency/receipt/place collapse to one tap each. ② Inline Equal/Custom split with live per-person shares. ③ Pinned lime CTA with running total + smart defaults (You paid · Equal · last category).

### H3 — Give Balances a summary "head"
**Screens:** Balances · `03-balances.png`
Built screen opens on per-pair cards, no glance answer. ① Net-balance donut hero (owed vs owe). ② One lime "Settle up" CTA; avatars + scannable rows replace the text list. Settle engine unchanged.

### H4 — Build the Trip Map (journey replay) — the concept's moat
**Screens:** Trip Map *(roadmap W3, not built)* · `04-trip-map.png`
README calls it "the moat"; exists only as a fake door. ① Every member's trail on one timeline, each a brand color, toggleable; moments pinned to the route. ② A day scrubber drives replay. Data hooks exist (receipt EXIF, per-expense places).

### H5 — Build Trip Wrapped (share the story) — the missing brand pillar
**Screens:** Trip Wrapped *(roadmap W3 / Tally, not built)* · `05-trip-wrapped.png`
Brand promise = "split · capture · share the story"; the story is a "coming soon" door. ① Tap-to-advance recap story (totals, distance, photo/city counts, superlatives), every frame share-ready with watermark. ② Lime "Share your Wrapped." Highest-emotion share + retention hook at trip close.

### H6 — Add to Plan: type-first, smart per-type forms  *(NEW this pass)*
**Screens:** Add to Plan *(Wave 2)* · `07-add-to-plan.png` · refined Visit: `09-add-to-plan-refined.png` · all six types: `11-add-to-plan-types.png` · flight-number resolution: `12-flight-resolved.png`
Today every plan item — museum, flight, hotel — funnels through one generic form with a buried type dropdown (~12 taps; fields that don't apply). ① **Type tiles up front** — Visit · Train · Flight · Transfer · Lodging · Other; one tap sets context + colors the sheet. ② **Per-type smart forms**: Visit opens **POI search with resolved places** (tap to pick, no address typing); Train/Flight ask from→to; Transfer adds a mode; Lodging is check-in/out; times are optional, not a gate. ③ One pinned lime CTA — typical add is **type → place → done** (2–3 taps). Bonus: a placed Visit becomes a free pin on the Trip Map (H4).

**H6a — Visit search & color cleanup (from live build, `09-add-to-plan-refined.png`):** the shipped Place field is a **nested double-box** (purple outer container + oversized search-icon column wrapping a second teal-bordered input) that squeezes the typing area, and the screen has **four accents fighting** (purple + teal + coral + lime) with an empty **Notes** block ranked *above* the Place field. Fixes: one clean search pill (small inline icon, full-width text, clear ×); **one accent per type** (Visit = coral for selected tile, search icon, focus ring, suggestion highlight — purple/teal borders removed; **lime reserved for Save only**); re-order Place → live suggestions → Address (optional) → collapsed "Add a note"; tighten three helper lines to one; nothing truncates.

**H6b — Per-type forms (Train · Flight · Transfer · Lodging · Other, `11-add-to-plan-types.png`):** each type keeps the shared shell (type-picker, one accent per type, pinned lime CTA) and shows only its relevant fields. **Flight resolves by flight number** (`12-flight-resolved.png`) — type/tap a flight (e.g. TP 542) and airline, route, departure/arrival airports + times, terminals, date and aircraft auto-fill into a boarding-pass-style card; Seat + booking ref stay optional. Train = stations + departs/arrives (+ optional train no.); Transfer = mode chips (Car/Taxi/Ferry/Bus/Walk) that re-label the reference field, plus pick-up/drop-off; Lodging = stay search with resolved result + check-in/out (nights auto-counted) + confirmation; Other = free title + optional place/time/note.

### H7 — Plan view (the itinerary) — coherent with Add to Plan  *(NEW this pass)*
**Screens:** Plan *(Wave 2)* · `10-plan-view.png`
The screen Add-to-Plan feeds into was missing. A **day-grouped time-rail timeline** that reuses the exact type system: each item carries its type's accent + icon (Visit coral · Train teal · Flight cyan · Transfer orange · Lodging purple · Other gray) as a colored dot on the spine + tinted icon; **lime stays on the "Add to plan" button only**. ① **POI thumbnails** — place types (Visit, Lodging) show the resolved photo with a small type-color badge; transport keeps its icon tile (no photo exists). ② **Distance between stops** — a quiet "400 m · 6 min walk" pill on the spine, shown only between two located stops (hidden around a Transfer/Flight, which already is the travel leg). ③ **Inline RSVP** (Going / Maybe) on the item. Day pills scroll the trip's dates; empty days get a gentle add prompt. One entry → three surfaces (Plan, Map, Wrapped).

---

## Medium Priority

### M1 — Resolve global vs. per-trip duplication
**Screens:** Activity tab vs trip "Recent activity"; Expenses tab vs per-trip · `08-review-notes.png`
Make global tabs unambiguous aggregations that drill into per-trip views. Expenses tab = cross-trip money home (balance header + per-trip rollups + period strip) and home for the FAB's "+expense" trip-picker.

### M2 — Android platform hygiene (apply globally)
M3 `NavigationBar` + docked FAB (not a hand-rolled `BottomAppBar`); edge-to-edge + predictive back (Android 14+); dynamic-type-safe layouts (retire hero magic numbers, see M3); Credential Manager sign-in; 48dp targets; brand palette locked over Material You.

### M3 — Harden the trip-hero layout
**Screens:** Trip Dashboard
Hero height is hand-computed from magic constants + post-frame `setState`; fragile under long names, large fonts, RTL. Move to `CustomScrollView` + `SliverAppBar`.

### M4 — Profile / settings structure  *(now mocked)*
**Screens:** Profile · `06-profile.png`
Was a flat run of headers. ① Profile header (avatar + name + warm "Si va? · 6 trips together" on the brand gradient). ② M3 list sections — leading icons, trailing current-value text, dividers. ③ Pinned "Save changes" (ink, not lime — settings save isn't the signature action). Keeps the discipline: primary here is never lime.

### M5 — Warm up Auth / onboarding
**Screens:** Auth · `08-review-notes.png`
Works (email OTP + Apple/Google + QR) but reads like default Material; first impression. Warm toward the board (gradient/pattern); render the real wordmark asset instead of text "VAMO". (Wordmark delivered — see `brand-out/`.)

### M6 — Surface daily-value moments (Plan/Events)
**Screens:** Plan / Events *(Wave 2)*
RSVP chips match the board. To earn daily opens, surface "next up" on the trip dashboard and home Activity — not only inside the Plan tab. Pairs with H6.

---

## Low Priority

- **L1 — Quick-actions discoverability:** 5 fixed 76px tiles in a horizontal scroll push items off-screen; use a 2-row wrap / prioritized set.
- **L2 — Photo-less trips look identical:** seed gradient/pattern from destination until photos/theme packs (Wave 2).
- **L3 — Settle-up state clarity:** make "pending confirmation" a visibly distinct, quiet state.
- **L4 — Activity feed polish:** move off M2 Card+ListTile to M3; add trip thumbnails/avatars.
- **L5 — Snapshot share theming:** wire destination theme packs (Wave 2); keep watermark; Wrapped (H5) feeds from the same composer.

---

## Open Questions

1. Wave-1 stopgaps: do Trip Map (H4) and Wrapped (H5) ship as the W3 concepts shown, or as polished "coming soon" fake doors now to measure intent?
2. FAB context rules: exact "+" mapping per tab; what does "+" do on Profile?
3. Global vs per-trip (M1): pure aggregators, or retain standalone create entry points?
4. Material You: fully override dynamic color with the locked palette (recommended)?
5. Web share pages (roadmap W2): in/out near-term? They close the invite loop for non-installers.
6. Wrapped data: are distance + photo counts reliably available at close for the first cut?
7. **Add to Plan (H6):** which POI provider resolves places, and do we cache resolved POIs per trip for offline + Map reuse?

---

## Screens / Flows Referenced

| # | Screen / Flow | Status | Asset |
|---|---|---|---|
| 01 | Main shell / nav + FAB | Built (4-slot) | `01-navigation-fab.png` |
| 02 | Add Expense | Built | `02-add-expense.png` |
| 03 | Balances (trip + tab) | Built | `03-balances.png` |
| 04 | Trip Map / journey replay | Roadmap W3 — not built | `04-trip-map.png` |
| 05 | Trip Wrapped / recap story | Roadmap W3 (Tally) — not built | `05-trip-wrapped.png` |
| 06 | Profile / settings | Built | `06-profile.png` |
| 07 | Add to Plan (item types) | Wave 2 | `07-add-to-plan.png` |
| 07a | Add to Plan — search & color cleanup | Wave 2 | `09-add-to-plan-refined.png` |
| 07c | Add to Plan — all six type forms | Wave 2 | `11-add-to-plan-types.png` |
| 07d | Add to Plan — flight-number resolution | Wave 2 | `12-flight-resolved.png` |
| 07b | Plan view (itinerary timeline) | Wave 2 | `10-plan-view.png` |
| 08 | Auth, Expenses tab, Activity, Plan, Members & invite, Snapshot, Close report, Web share | mixed | `08-review-notes.png` |
| — | Overview / index | — | `00-overview.png` |

---

## Implementation Notes

- **Interactive mockups:** `Vamo UX Improvements.dc.html` (editable) and `Vamo UX Improvements (standalone).html` (offline). Live: expense keypad + split, balances, map scrubber + trail toggles, Wrapped tap-through, and **Add-to-Plan type picker + POI pick**. Tweaks: Annotations on/off; action color.
- **Keep as-is (validated):** minimal-transaction settle engine; "Vamo never moves money" deep-link model; sanitized errors; solo trips hiding Balances; fake-door signal stack; contrast governance (goLime fill-only, coralText for small text).
- **Sequencing:** H1 + H2 first (highest-leverage, mostly front-end); H3 follows; H6 is Wave-2 and self-contained — good parallel track; H4/H5 net-new W3 (decide stopgap, Open Q1). M2/M3 fold into the nav work and dashboard pass.
- **Color rule:** lime (`#C6FF00`) = single primary action per screen (FAB, Settle, Save expense, Share Wrapped, Add to plan) — never decorative; small text uses coralText.
- **Metrics:** H2 → `flow_abandoned`; H5 → day-after-close retention ≥35%; H1 + invite + web share → viral coefficient; H6 → Plan adoption / daily opens.
