# S46 — In-app notification center (record-first; push becomes best-effort)

**Why this is load-bearing, not cosmetic.** Today lifecycle notices (`trip-lifecycle-jobs`)
are **FCM-push-only with zero persistence**: no `notifications` table, no inbox. Worse, the
job stamps `close_notified_at` **only when a push is delivered** (`index.ts` ~line 99, inside
`if (result.sent > 0)`). So a member with no registered device (uninstalled, push denied,
web) is **never notified → the 14-day deemed-close clock never starts → the trip can't
auto-close**. "Silence = consent" silently breaks for exactly the silent members. This slice
makes notices a **recorded source of truth** and decouples the closure clock from push.

**Hard dependency:** the `trip-lifecycle-jobs` pg_cron schedule stays **disabled** until this
ships AND the close-notice is verified delivering to a real 2nd device. (S22 merged push-only
on that condition.)

The bell already exists — `feature_split/.../trips/trips_list_screen.dart:235`
(`Icons.notifications_outlined`) — wired to nothing. This slice gives it a backend + inbox.

---

## A. Data layer — migration `0031_notifications.sql`
Create `public.notifications` as the source of truth:
```
id          uuid primary key default extensions.gen_random_uuid()
user_id     uuid not null references auth.users(id) on delete cascade
trip_id     uuid references trips(id) on delete cascade        -- nullable (non-trip notices)
type        text not null   -- close_notice | close_reminder | deemed_closed | settle_nudge | ...
title       text not null
body        text not null
route       text            -- deep-link target, e.g. /trips/<id>/close-report
created_at  timestamptz not null default now()
read_at     timestamptz
```
- Index: `(user_id, created_at desc)`; partial `(user_id) where read_at is null` for the badge.
- **RLS:** owner-only read (`user_id = auth.uid()`); **no client INSERT** (service/RPC only,
  mirror the lifecycle-guard pattern in 0029). Add SECURITY DEFINER RPCs:
  - `record_notification(p_user_id, p_trip_id, p_type, p_title, p_body, p_route)` — service-role
    only; returns the row id. (Single insertion point for the edge fn.)
  - `mark_notification_read(p_id)` — caller may mark only their own (`user_id = auth.uid()`).
  - `mark_all_notifications_read()` — same, all own unread.

## B. Edge function — record-first, push best-effort
`supabase/functions/_shared/`: add `recordNotification(supabase, {userId, tripId, type, title,
body, route})` → calls the `record_notification` RPC.

In `trip-lifecycle-jobs/index.ts`, at **each** of the four send-sites (close_notice ~83,
reminder ~131, deemed_closed ~185, settle_nudge ~212):
1. **`recordNotification(...)` FIRST** — this is the durable notice.
2. **Move the state stamp OUT of the `sent>0` gate.** `_stamp_member_close_notified` (line 99),
   `mark_close_reminder_sent` (line 149), etc. must fire on **record creation**, not push
   success — so the deemed-close clock starts for everyone. **This is the P0 correctness fix.**
3. Then `sendPushToUserDevices(...)` as **best-effort** delivery; keep `push_sent`/`push_failed`
   stats, but the notice no longer depends on them.
Result shape: add per-type `*_recorded` counts alongside the existing `push_*` counts so a run
is observable even with zero devices (fixes the "all-zeros tells us nothing" gap we hit).

## C. App — offline-first + the bell
- **Drift:** add `localNotifications` table mirroring the columns; bump `schemaVersion` 15 → 16
  with a `from < 16` migration step; sync via the existing `sync_worker` pull (notices are
  read-only on device — pull only, no outbox). Follow the existing entity-sync pattern.
- **Providers:** `notificationsProvider` (list, newest first) + `unreadCountProvider`
  (`read_at == null`), both off the Drift stream (reactive).
- **Bell:** wire the existing `trips_list_screen.dart:235` icon — overlay an unread **badge**
  (count, capped "9+"), `onTap` → push `NotificationsInboxScreen` via go_router (add route).
- **Inbox screen:** list rows (icon-by-type, title, body, relative time, unread dot); tap →
  `mark_notification_read` + navigate to `route`; "mark all read" action; `AppEmptyState` when
  empty. Use `VamoCircleIcon` + tokens (light/dark), `MediaQuery.textScaler`-safe, full a11y.
- **i18n:** ARB strings for inbox title, empty state, "mark all read", and per-type templates.

## D. Tests (right layers — no framework-testing)
- **rls_smoke.dart:** A sees only own notifications; B cannot read A's; `mark_notification_read`
  only affects caller's row; client INSERT into `notifications` is blocked.
- **Drift migration test:** `drift_notifications_migration_test.dart` (15→16 adds the table).
- **Edge logic:** record-first — assert `close_notified_at` is stamped even when `sent == 0`
  (the load-bearing decoupling); per-type `*_recorded` increments.
- **Widget:** bell shows correct unread badge from provider; tap opens inbox; mark-read clears
  the dot. (Provider-driven, deterministic — not image/framework behavior.)

## E. Guardrails / done =
- Notice **record** is source of truth; push is best-effort; closure clock keyed to record
  creation. `melos run ci` green; rls_smoke green (now N+ checks).
- **Device gate (the one S22 deferred):** on 2 devices, request close → run job → the non-actor
  **sees the notice in their bell/inbox even with push off**, and (push on) also gets the FCM.
- **Only after this + the 2-device pass:** enable the `trip-lifecycle-jobs` pg_cron schedule
  (`docs/SCHEDULED_JOBS.md`).

## Notes
- Migration is `0031` (cloud/main at 0030). Drift schema 15 → 16.
- Pairs with the closure model ([[docs/design/CLOSURE_PATTERNS.md]] / closure memory): this is
  what makes "silence = consent" actually hold.
- Future notice types (invites accepted, expense disputes, RSVP changes) reuse the same table +
  bell — build the pipe once.
