# Wave 2 — planning seed

Input for the Wave-2 spec session (run the Wave-1 drill: spec → build plan →
sliced backlog). Collects everything approved or queued for the wave so far.
Not a spec yet — estimates are rough, sequencing TBD at planning.

## Core (from roadmap)

1. **EventList** (`feature_events`) — group events with RSVP + guest list.
2. **TripBoard** (`feature_board`) — collaborative itinerary + shared lists.
   Together: the "open daily during the trip" stickiness wave.
3. **AI theme resolver** — spec ready: `docs/AI_THEMING_SPEC.md`
   (Edge Function + `destination_themes` global cache + client ladder). ~2d.
4. **Web share-pages** (`web/apps/share-pages`) — view-before-install behind
   invite links. **Blocked by the name/domain decision.** ~2–3d.
5. **Snapshot themes v2** — full pack library + photo backgrounds behind
   Voyager entitlement (watermark permanent, per doctrine).

## Approved from the AI-idea ledger (2026-06-05)

6. **QR invite** (~0.5d) — render the existing invite token as a QR on the
   Vamigos tab ("show this to your crew"); scanning opens the join deep link.
   No backend change; `join_trip` untouched. Add `member_invited` property
   `channel: qr|link`. Strongest viral-coefficient lever per cost in the wave —
   consider making it Wave 2's FIRST slice so it reaches testers early.
7. **Trip budget & burn-down** (~1d) — optional `budget_cents` on trips
   (migration), burn bar + "€X left" chip on trip home computed from existing
   expense data; nudge color past 80%. Events: `budget_set`, property
   `over_budget` on trip stats. No new services.
8. **Settle-up nudge** (~1d, needs push plumbing T10.5 finished) — scheduled
   check (pg_cron or Edge Function): trips past `end_date` with non-zero
   `trip_balances` and open settlements → one push per member, once
   ("2 open balances — si salda?"). Deep-links to Balances. Anti-nag rule:
   max 1 nudge per trip, ever, unless a new expense lands after it.
9. **OCR scan-to-fill + place** — **PROMOTED to first Wave-2 slice alongside
   QR invite (founder decision 2026-06-05).** On-device ML Kit text recognition
   pre-fills amount/currency/title AND extracts the merchant/place name into a
   new `place_label` on expenses (shown on the expense row — the first visible
   "where" in the product, pre-TripMap). User always confirms before save.
   Retroactive backfill command over already-stored receipts (Slice 14 stored
   the images + EXIF precisely to enable this). Offline-capable, zero cloud
   cost. Cloud fallback deferred.

## Identity pass (critical path, runs with the name decision)

Founder review 2026-06-05: current UI is engineering-built and identity-free —
palette clashes with the colorful brand vision, logo appears nowhere, gear-only
navigation reads amateur. Scope: design critique from screenshots + founder
references → design brief → app_core token overhaul (single point, propagates) →
bottom navigation (Trips / + / Profile&Settings; Events joins in Wave 2) →
logo/wordmark placement (app bar, empty states, splash, launcher icon).
**Blocked by and forces the name decision** (logo/wordmark = the name).
Slice 15 (About: version, brand block, licenses, privacy policy URL) folds in.

## Carried context

- Receipt capture metadata is EXIF-only in Wave 1 (no device-location permission).
  Device-location tagging returns with TripMap's opt-in flow (Wave 3).
- Pricing mechanics decided for later waves live in the roadmap Extras
  (immersion unlock pay-or-grow, popularity-gated imagery) — not Wave 2 scope.
- i18n: any new Wave-2 screen must follow `docs/I18N_PLAN.md` rules from its
  first commit (directional layouts, ARB strings, bidi-safe money).
- Every new surface wires the §8b signal layers + safe-error presentation
  by default (spec'd patterns exist; reviewers enforce).

## Gate reminder

Wave 2 itself ends at a go/kill gate before Wave 3 (TripMap). The wave's
success metric is stickiness: DAU-during-active-trip and day-after-trip
retention — instrument from day one so the gate has data to judge.
