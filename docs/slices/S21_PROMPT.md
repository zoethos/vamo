# S21 — EventList + RSVP + Activity enrichment (W2·R8)

**Branch:** `feature/eventlist` · **Est:** ~1.5 dev-days · **Depends:** S18 (plan items) merged
**Spec:** `Vamo_Wave2_Spec.md` R8 · builds on S18's `trip_plan_items` (events = `kind='activity'`)
**Out of scope:** event reminders / recurring events (spec P2), notifications on RSVP (S22 push), calendar export

> Standard patterns (now house style): RPC-only mutation via GUC trigger,
> RLS writes `is_trip_member AND is_trip_writable`, **restrictive DELETE**,
> ARB strings from the start (parameterized, no concat), state-based smoke,
> negative-assertion widget tests, no hardcoded English, online-only deliberate
> only if documented. SECURITY DEFINER readers re-check membership.

## 1. Migration `0022_event_rsvp.sql`

Events are existing `trip_plan_items` rows with `kind='activity'` — **do NOT
add an events table** (S18 designed for this). Add only RSVP:

- enum `rsvp_status`: `going | maybe | declined` (no "pending" — absence of a
  row = not responded; keeps it clean and avoids a backfill).
- `trip_plan_item_rsvps`: `id`, `plan_item_id` fk → trip_plan_items(id) on
  delete cascade, `user_id` fk profiles, `status rsvp_status not null`,
  `responded_at timestamptz not null default now()`, unique `(plan_item_id,
  user_id)`.
- index on `(plan_item_id)`.

RLS:
- SELECT: caller is a member of the plan item's trip (join through
  `trip_plan_items.trip_id` → `is_trip_member`).
- INSERT/UPDATE: **own row only** (`user_id = auth.uid()`) AND
  `is_trip_member` AND `is_trip_writable` of the parent trip. RSVP is a
  personal act — like share response, a member sets only their own.
- DELETE (withdraw RSVP): own row only; **restrictive** `is_trip_writable`
  companion (closed-trip RSVP frozen, consistent with S17 read-only chrome).

RPC `set_event_rsvp(p_plan_item_id, p_status)` — upserts caller's own row;
validates the parent is `kind='activity'` and trip writable + member. Revoke
public / grant authenticated, GUC-gated like the others. (Personal own-row
write; no admin gate — any member RSVPs to any event in their trip.)

## 2. Flutter

- Drift v13: `trip_plan_item_rsvps`; sync handler; pull in trip sync.
- `PlanRepository` (or a small `EventRepository`): `setEventRsvp`, and a
  read model joining counts (going/maybe/declined) + caller's own status per
  event.
- UI:
  - Plan tab: `activity`-kind items render as **events** with date/place and
    an RSVP control (Going / Maybe / Declined) + a count summary
    ("3 going · 1 maybe"). Non-activity plan items unchanged.
  - Creating an event = creating a plan item with `kind=activity` (reuse the
    S18 add/edit sheet; surface the RSVP affordance once it has activity kind).
  - Read-only chrome (S17): RSVP control disabled on closed/cancelled trips.
- **Activity feed enrichment (the R8 "shows them" clause):** the Activity tab
  feed includes event creation + RSVP changes across the user's trips,
  chronological, same pattern as expense/settlement/member events. No amounts.
- ARB strings (parameterized counts — `eventRsvpSummary(going, maybe)` etc.),
  directional.
- Analytics: `event_created` (reuse `plan_item_created {kind:activity}` if
  cleaner), `event_rsvp {status}` — no titles, no PII.

## 3. Verification

`tool/rls_smoke.dart` (state-based, ≤1 live external call rule N/A — no external):
- B sets own RSVP on an event → row appears with status
- B updates own RSVP → status changes (not a 2nd row; unique holds)
- B cannot set RSVP for another member (own-row only)
- C outsider cannot RSVP / cannot read RSVPs
- RSVP on closed trip → blocked; on cancelled → blocked (incl. DELETE)
- RSVP on a non-activity plan item (e.g. lodging) → rejected by RPC
- ex-member RSVP blocked

Unit: rsvp count aggregation; "not responded = no row" handling.
Widget (negative assertions): RSVP control **absent/disabled** on a closed
trip; RSVP summary renders from counts not literals; non-activity items show
no RSVP control. `melos run ci` green + smoke PASS on cloud.

## 4. RUN.md — Slice 21 demo: create an activity event → two devices RSVP →
counts update → appears in Activity feed → close trip → RSVP frozen.

## 5. Reviewer checklist
- [ ] No new events table — events are `trip_plan_items kind='activity'` (S18 reuse)
- [ ] RSVP is own-row-only (member can't set another's); restrictive DELETE present
- [ ] RSVP frozen on closed/cancelled (S17 chrome consistency)
- [ ] RPC rejects RSVP on non-activity plan items
- [ ] Activity feed shows event create + RSVP (R8 "shows them")
- [ ] Zero hardcoded strings; parameterized ARB counts; negative-assertion tests
- [ ] No titles/PII in analytics
