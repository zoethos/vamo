# S21 review fixes — EventList + RSVP (pre-merge)

**Branch:** `feature/eventlist` · **Gate:** all four fixed → `melos run ci` green
+ `dart run tool/rls_smoke.dart` PASS on cloud + 2-device realtime check → then merge `--no-ff`.
**Context:** S21 schema direction is correct (no events table, `kind='activity'`
reuse, own-row upsert, non-activity rejection, closed/cancelled freeze). These
are the four review findings that block merge. `0022` is **already pushed to the
cloud DB**, so additive changes go in a **new `0023` migration** — do NOT edit
`0022`.

---

## Fix 1 (P1) — Cloud smoke aborts on the cancelled-RSVP case (ordering bug)

**Where:** `tool/rls_smoke.dart` (~L917 cancel, ~L946 insert).
**Root cause:** the cancelled-trip RSVP case cancels `cancelTripId` first, then
inserts a `kind='activity'` plan item into the now-**cancelled** trip — and
**outside a `try`**. S18 RLS requires `is_trip_writable`; a cancelled trip is
not writable → `42501` → uncaught → the run aborts (this is the `unexpected
error` FAIL; remaining checks are skipped).
**Fix:**
- Create the activity plan item **before** `cancel_trip`, while the trip is
  writable, and via the **plan-item RPC path** (the same one the passing
  `B insert plan item` check uses — GUC-flagged), not a raw
  `.from('trip_plan_items').insert()`.
- **After** cancellation, call `set_event_rsvp` and assert it is **blocked**
  (wrap in the expect-failure helper like the other negative cases).
- Re-confirm the existing `RSVP on cancelled trip blocked` assertion still holds.

---

## Fix 2 (P1) — RSVP / event changes don't propagate via Realtime

**Where:** `supabase/migrations/0022_event_rsvp.sql:146` adds
`trip_plan_item_rsvps` to the Realtime publication, but the subscriber
`packages/app_core/lib/src/sync/trip_realtime.dart:67` listens only to
expenses, settlements, members, notes, photos — **not** `trip_plan_items`,
`trip_list_items`, or `trip_plan_item_rsvps`. RSVP rows also have no `trip_id`
for the existing trip-scoped filter. Result: another device's event creation or
RSVP won't refresh the Plan tab / Activity feed until a full/manual sync. (Note:
this also fixes a latent S18 gap — plan/list items weren't realtime either.)
**Fix (reuse the S19 parent-touch pattern — preferred over denormalizing
`trip_id` onto rsvps):**
- **`0023`:** in `set_event_rsvp` (and the new `clear_event_rsvp`, Fix 3),
  **touch the parent `trip_plan_items` row** (`updated_at = now()`) so a
  trip-scoped subscription fires. `trip_plan_items` already has `trip_id`.
- **Subscriber:** add realtime listeners for `trip_plan_items` **and**
  `trip_list_items`, filtered by `trip_id` (same shape as the existing
  expense/member subscriptions). On event, trigger the existing plan/RSVP
  re-sync so counts + the caller's status refresh.
- This avoids adding `trip_id` to `trip_plan_item_rsvps` (no row-filter that
  Realtime can't express) and keeps one consistent pattern.

---

## Fix 3 (P2) — RSVP deletes bypass the "RPC-only writes" guarantee

**Where:** `0022_event_rsvp.sql:33` guard trigger covers INSERT/UPDATE only;
`:79` allows direct member DELETE while writable.
**Decision:** row-absence = "not responded" **is** intentional (per S21 spec),
so *withdraw* must exist — but a raw DELETE bypasses analytics and any future
audit, and breaks the "all RSVP mutations go through an RPC" story.
**Fix (make the claim true):**
- **`0023`:** add `clear_event_rsvp(p_plan_item_id)` — GUC-guarded, own-row,
  `is_trip_member` + `is_trip_writable`, parent-touch (Fix 2). Emits the same
  analytics shape as set (e.g. `event_rsvp {status: 'withdrawn'}` — no PII).
- Keep the **restrictive DELETE policy** as defense-in-depth (own-row +
  `is_trip_writable`), but route the app's "withdraw RSVP" action through
  `clear_event_rsvp`, not a direct delete.
- Smoke: add `B withdraw own RSVP via RPC` (row gone) and
  `withdraw on closed trip blocked`.

---

## Fix 4 (P3) — Activity feed shows raw `going`, not the localized label

**Where:** `packages/feature_split/lib/src/activity/activity_repository.dart:99`
stores the raw status string; `activity_screen.dart:112` passes it straight into
`activityEventRsvpSubtitle` → users see `RSVP: going`.
**Fix:** map the status through the **same RSVP label bundle** used by the Plan
tab chips (Going / Maybe / Declined) before building the subtitle, so the
Activity feed reads `RSVP: Going` localized. No new ARB if the chip labels
already exist — reuse them; the feed must not format raw enum values.

---

## Verification (all required before merge)

- `melos run ci` green (unit + widget incl. negative assertions; add the
  withdraw-RPC widget/unit cases).
- `dart run tool/rls_smoke.dart` **PASS on cloud** — no `unexpected error`;
  new checks: withdraw-via-RPC, withdraw-on-closed-blocked.
- **2-device realtime check** (the gap smoke can't cover): device A creates an
  event + RSVPs; device B's Plan tab counts and Activity feed update **without**
  a manual refresh. This is the acceptance proof for Fix 2.
- Then merge `feature/eventlist` → `main` `--no-ff`; tracker stays "in review"
  until merge + push is confirmed.

## Migration note
`0022` is already applied on the cloud DB — put all SQL changes (parent-touch in
`set_event_rsvp`, `clear_event_rsvp`, any policy tweak) in **`0023_event_rsvp_realtime_and_clear.sql`**.
Do not edit `0022`.
