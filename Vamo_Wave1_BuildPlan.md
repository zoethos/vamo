# Vamo — Wave 1 Build Plan

**From planning to build.** This turns the Wave 1 spec's 10-step build order into a sequenced, estimated backlog you can execute and track. Companion file: `Vamo_Wave1_Backlog.xlsx` (every task with estimate, dependency, sprint, priority, acceptance mapping, and a status column).

## The honest timeline

Bottom-up, the P0 scope is **~28 focused dev-days**. The spec's "1–3 weeks" target only holds if you run long days or already have boilerplate (auth, design system, Drift sync) lying around. At a sustainable solo pace, plan for **~5–6 calendar weeks**; if you're sprinting hard, ~3 weeks is the floor. The three sprints below are sequencing units, not fixed calendar weeks — finish a sprint, then start the next.

## Sprint A — Foundations (~8.5 days)

Stand up the backend and the app shell. Backend (T1.x) and Flutter scaffolding (T2.x) are largely independent, so you can ping-pong between them while one waits on the other (e.g. provider config propagating).

Get Supabase live first: project, run `vamo_wave1_schema.sql`, wire the four auth providers and the profile-creation trigger, set up private storage buckets, and do a first RLS-tester pass so privacy is proven before any feature sits on top of it. The daily FX cache lands here too. In parallel, scaffold the monorepo (`app_core` + `feature_split`), the Supabase client and session handling, Riverpod + router, the teal/sand design system, the Drift local DB, the PostHog analytics wrapper, and i18n. Nothing user-facing ships this sprint — but everything after it goes faster because of it.

**Exit:** a logged-in shell talking to Supabase, RLS proven, design system and offline cache in place.

## Sprint B — Core split flow (~12 days)

This is the product. Build the SplitTrip loop end-to-end: auth/onboarding screen, trips list with the "Si va?" empty state, create trip (solo or invite), the trip-home hub (Balances hidden for solo), members + invite link, and deep-link `join_trip` (including mid-trip join). Then expenses: the add-expense screen with equal/custom splits, the `sum(shares)==base_cents` invariant on write, and the FX snapshot for non-base-currency costs.

Settle-up is the trust-critical piece. **Build the `settleUp()` engine and its unit tests early in this sprint** — it's pure, deterministic, and independent of the UI, so it's the lowest-risk thing to lock down (equal, custom, multi-payer, multi-currency, 3-person cycle). Then the Balances screen reads `trip_balances`, renders the minimal "X pays Y" list, and mark/confirm writes settlements and deep-links to Venmo/PayPal/Wise. Vamo never moves the money.

**Exit:** a group can create/join a trip, log multi-currency split expenses, see a correct minimal settle-up, and mark + confirm — the spec's acceptance criterion 2, fully.

## Sprint C — Growth + ship (~7.5 days)

The growth seed and the runway to ship. Build the branded snapshot card (trip, totals, avatars, teal/sand, wordmark), rasterize to PNG, push to the share sheet, and fire `snapshot_shared` — this is the Wave-1 seed of the broadcast loop. Add solo capture (title, notes, photos feeding the snapshot), then the offline sync worker (optimistic writes, last-write-wins reconciliation) and the realtime per-trip channel. Finish with the settings screen, empty/error-state polish, an analytics QA pass (all 7 events), an end-to-end RLS QA pass, and the build to TestFlight / Play internal. Basic push is the one stretch item — cut it if the clock is tight.

**Exit:** all six Wave-1 acceptance criteria met; build in internal testers' hands.

## How to work the backlog

**Sort by `Slice` first** — it's the primary execution key. Within a slice, rows are in `ID` order, which already respects dependencies. Each slice ends in something you can demo on a device, so "what am I building toward this week?" is always a slice, not a layer. Keep **Sprint** as a rough capacity bucket only.

For the first demo deadline, filter **Milestone = Spine** (slices 0–4): that's the solo→split→settle story and the first shippable thing. **Depends on** tells you what must be green before a task can start — respect it and you'll never be blocked mid-task. Flip **Status** as you go (Not started → In progress → Done).

The **Slice summary** tab shows effort and cumulative days per slice (Spine lands at ~17 dev-days; full Wave 1 is ~28). The **Acceptance coverage** tab maps each of the 6 "done" criteria to the tasks that satisfy it.

## Slices: the vertical view

The sprints above are horizontal capacity buckets (backend, then core, then growth). The **slices** are the vertical cut you actually execute against — each one runs UI → logic → Supabase and ends in a demo on a device. The backlog's `Slice` column is now the primary sort; this is the order to build in.

| Slice | Milestone | Demo |
|------:|-----------|------|
| 0 | Spine | Log in → empty trips list |
| 1 | Spine | Create trip → persists → trip home |
| 2 | Spine | €30 dinner, equal split |
| 3 | Spine | Who owes whom + tests green |
| 4 | Spine | Mark settle → Venmo → confirm |
| 5 | Multiplayer | Second phone joins via link |
| 6 | Growth | $ expense on a € trip |
| 7 | Growth | Share branded card |
| 8 | Growth | Solo capture → snapshot |
| 9 | Hardening | Airplane mode + live co-edit |
| 10 | Hardening | TestFlight / Play internal |
| 11 | Signals | Product signals — friction, intention doors, suggestions (AC7) |
| 12 | Themes | Snapshot theme packs — keyword-matched, free (Wave 2 seed) |
| 14 | Evidence | Scan receipt on add expense → thumbnail on list → full-screen viewer |

**Spine (slices 0–4) is the first shippable story** — a solo or in-person group can create a trip, split costs, and settle up. That's the milestone to aim the first internal build at. **Slice 5 is the inflection point**: it turns the app multiplayer via invite links.

Two tagging notes worth keeping straight. The analytics task **T2.6** sits in Slice 0 — it's the debug/stub seam (already present in `analytics.dart` with all seven events enumerated); the *PostHog QA* that verifies events actually fire is its own task, **T10.3**, in Slice 10. And **T2.7** (i18n) is in Slice 0 because the spec wants strings externalized from day one, and it's cheapest to do while the first screens are being written.

**Slice 11 (milestone Signals, backlog T11.1–T11.6)** implements spec **§8b** after ship prep: UX friction events (`screen_viewed`, `error_shown`, `empty_state_shown`, `flow_abandoned`, `action_failed`), three intention doors (Plus, trip map, recap video), and suggest-a-feature (`0006_suggestions.sql`). Acceptance criterion **AC7** depends on this slice; **T11.6 (Signals QA)** stays open until PostHog and cloud RLS checks pass. **Slice 12 — Themes** (T12.1–T12.3) follows: keyword-matched snapshot theme packs (first Wave 2 work, tracked in the Wave-1 backlog for continuity). **Slice 14 — Receipt attachment** (T14.1–T14.3): optional receipt photo on add expense (`0008_expense_receipts.sql`), EXIF/device capture metadata, list thumbnail + signed-URL viewer, sync + `has_receipt` analytics. Parked for later waves: OCR scan-to-fill, receipt→TripMap stops, place-photo matching.

One milestone gap to flag: the slice proposal labelled Spine (0–4), Multiplayer (5), Growth (7–8), Hardening (9–10) and left **Slice 6 (multi-currency)** unassigned. I've grouped it under **Growth (6–8)**, since multi-currency is what unlocks international trips rather than part of the single-currency spine demo. Easy to move if you'd rather it read differently.

**The ordering tension this fixes:** invite/join (`T4.2`/`T4.3`) lives in Sprint B right next to create-trip, which made it tempting to schedule before the settle-up engine. As slices, it's correctly **Slice 5 — after the solo spine (0–4)**. Sorting the backlog by `Slice` makes that explicit and stops accidental "invite before balances" scheduling.

## Two flags before you start

The biggest single risk is **offline sync (T9.1)** — last-write-wins per field is simple to describe and fiddly to get right with optimistic UI; budget the full 1.5 days and lean on it during QA. Second: the **`vamo.app` deep-link domain and the working name itself** carry the ownability risk already noted in planning — confirm the domain and store-listing name are locked before T4.2/T4.3, since changing them after links are live is painful.
