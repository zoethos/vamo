# S22 — Close report + lifecycle nudges + cron enablement (W2·R7)

**Branch:** `feature/close-report` · **Est:** ~2–2.5 dev-days · **Depends:** S17 lifecycle (merged), S16 push (`send-push` working)
**Constitution:** `docs/design/CLOSURE_PATTERNS.md` (deemed acceptance), `MONEY_GOVERNANCE.md` D2 (closure), `docs/design/NOTIFICATIONS.md` (notification guardrails)
**Out of scope:** the unified notifications **inbox** (W3 — S22 is a *producer*, it sends push + optionally writes an activity row, it does NOT build the inbox); referral; new dispute concepts.

**Current repo note (2026-06-07):** PR #20 is held, and its branch still contains
`supabase/migrations/0025_s22_close_notice.sql`. Production already has S25's
`0026_s25_get_trip_preview.sql` applied. When S22 resumes, rebase onto `main`
and rename/recreate the S22 migration at the **next free ordinal at that time**
(especially if S23 ships first). Do not merge or push the stale `0025` slot
unchanged.

> This slice makes the S17 closure dance **actually fire**: the lifecycle cron
> (`trip-lifecycle-jobs`, deployed but **unscheduled**) currently computes
> reminders/deemed-close/unresolved purely on time and sends **nothing**. The
> governing rule is **"no notice, no deemed consent"** — a trip may only be
> deemed-closed if the closing notice was actually sent. So nudges come first,
> then we enable the cron.

## 0. The four pieces (and their order)
1. **Member-targeted push** — a server-side (service-role) push path so the cron
   can notify a trip's *members* (today `send-push` only pushes to the *caller's*
   own devices via their JWT — unusable from cron).
2. **Lifecycle nudges** — wire notices into `run_trip_lifecycle_jobs` moments
   (close-requested, day-7 reminder, deemed-closed, settle nudge), gated by
   notice-sent so deeming is legitimate.
3. **Close report** — the "statement" view: balances, who accepted / objected /
   was deemed, disputes flagged.
4. **Cron enablement** — schedule `trip-lifecycle-jobs` **last**, only after the
   nudge path is device-verified. + **FCM UNREGISTERED pruning** (S16 finding).

## 1. Member-targeted push (the missing capability)
`send-push` signs an FCM v1 JWT (jose) and pushes to the **caller's** `push_devices`
rows. The cron has no caller — it runs as service-role and must push to *other*
users. So:

- **Factor the FCM send into a reusable helper** (the jose/FCM-v1 logic from
  `send-push`) so both `send-push` and the lifecycle job share one sender.
- The lifecycle job (service-role) resolves **target users → their `push_devices`
  rows** and sends via the shared helper. Never trust a client to say who to push.
- **FCM UNREGISTERED / NOT_FOUND → delete that `push_devices` row** inside the
  shared sender (S16 pruning, applies to both callers and cron).
- Respect `docs/design/PROVIDER_RESILIENCE.md`: handle FCM 429/5xx (don't crash
  the whole cron run on one bad token; collect + continue; log counts).

## 2. Lifecycle nudges — wire into `run_trip_lifecycle_jobs`
Extend the existing RPC + edge function (don't rebuild). Send a notice at each moment:

| Moment | Recipients | Copy intent (route → trip/close report) |
|---|---|---|
| **Close requested** (`closing`, on `request_trip_close`) | active members | "Trip is closing — review. Auto-closes in 14 days." |
| **Day-7 reminder** (`close_warned_at`, single-shot) | members who haven't accepted/objected | "5 days left to review *<trip>* before it closes." |
| **Deemed closed** (`closed`) | active members | "Trip closed. Settle up when ready." |
| **Settle nudge** | members with outstanding settlement | "You still have a balance to settle in *<trip>*." (no amount on lock screen) |

- **"No notice, no deemed consent":** add `close_notified_at` (trips) set when the
  close-request notice is actually sent. **Only deem-close** trips where
  `close_notified_at` is set AND the 14-day window elapsed. A trip that was never
  notified must NOT auto-close — it waits (or surfaces as an ops anomaly).
- **NOTIFICATIONS.md guardrails:** sparse, personal, actionable; **money/dispute
  content is lock-screen-sensitive** (title only, no amounts/balances on the lock
  screen); deep-link `route` to the trip / close report; ops alerts stay separate.
- Notices are **idempotent / single-shot** (reuse the `*_warned_at` / `*_notified_at`
  anti-nag pattern) — the daily cron must not re-spam.
- Tap → deep-link into the trip (and the close report when relevant), reusing the
  S16 push `route` plumbing.

## 3. Close report (the "statement")
- A **read model** computed from existing data for `closing` / `closed` /
  `unresolved` trips: final per-member balances (committed-only, consistent with
  S19/S20), who **accepted explicitly** vs **deemed** vs **objected** (CLOSURE_PATTERNS:
  "deemed ≠ hidden"), and **disputed shares flagged** (hard display rule — a
  disputed share never renders like accepted; force-close objections surface here
  as "included — objected by X", the squeeze-out/appraisal pattern).
- **Snapshot vs live (decision):** MVP may **compute live**; a frozen snapshot at
  deemed-close (immutable statement) is the cleaner long-term shape — flag it,
  don't build the snapshot now unless cheap.
- UI: a Close report screen reachable from the closing/closed trip (and the
  notice deep-link). Read-only chrome consistent with S17 (closed = no new
  expenses; settlements still allowed per A1).
- **No amounts in analytics**; ARB strings (parameterized), directional.

## 4. Cron enablement (LAST) + pruning
- After the nudge path is **device-verified**, schedule `trip-lifecycle-jobs`
  **daily** via Supabase Cron (Integrations → Cron; `x-cron-secret: CRON_SECRET`).
  Document the exact cron entry in `SCHEDULED_JOBS.md`.
- Enabling the cron is what makes trips actually auto-close on the timer — so it
  goes live **only** after a real device-verified nudge + a dry-run.
- FCM pruning (§1) lands with this.

## 5. Verification
`tool/rls_smoke.dart` (state-based, service-role for the job path):
- close-request sets `close_requested_at` + `close_notified_at`; deemed-close
  **only** fires when notified + window elapsed (assert a non-notified closing
  trip does NOT deem-close).
- day-7 reminder single-shot (`close_warned_at` not re-set on a second run).
- close report read model: deemed vs accepted vs objected reflected; disputed
  share flagged, never rendered as accepted; balances committed-only.
- settlements still writable on `closed`; blocked on `cancelled` (S17 regression guard).

Unit/widget (negative assertions): close report renders deemed/objected/disputed
states distinctly; no amounts on the push payload's lock-screen-visible fields.

**Device + cron gate (per the device-verify rule — CI/smoke can't see push/cron):**
- On the current Android stack: trigger a close request → **push arrives** on a *second* member's
  device (2-device), tap → routes to the close report.
- **Manually invoke** `trip-lifecycle-jobs` with the `CRON_SECRET` header (dry-run
  on a test trip past day-7) → reminder push arrives, `close_warned_at` set.
- Then enable the daily cron and confirm the next tick's `job_heartbeats` row.

`melos run ci` green + smoke PASS on cloud + the device/cron gate above.

## 6. RUN.md / SCHEDULED_JOBS.md
Document: the member-targeted push helper, the nudge moments, the close report
demo, and the **exact cron schedule entry** for `trip-lifecycle-jobs`.

## 7. Reviewer checklist
- [ ] Member-targeted push is **service-role / server-resolved** (client never says who to push)
- [ ] **"No notice, no deemed consent":** deemed-close gated on `close_notified_at`; un-notified trips don't auto-close
- [ ] Nudges idempotent/single-shot (anti-nag via `*_warned_at`/`*_notified_at`)
- [ ] NOTIFICATIONS guardrails: no amounts on lock screen; sparse; deep-link route; ops alerts separate
- [ ] FCM UNREGISTERED → `push_devices` row pruned (S16); FCM 429/5xx handled, one bad token doesn't fail the run
- [ ] Close report: deemed vs accepted vs objected exposed; disputed share never renders as accepted; committed-only balances
- [ ] Cron scheduled **only after** device-verified nudges; exact entry documented
- [ ] No amounts/PII in analytics; zero hardcoded strings; negative-assertion tests
- [ ] Device + 2-device + cron-dry-run gate passed before merge

## Notes / decisions to surface
- **Snapshot vs live close report** — MVP live; snapshot later (founder call).
- **Activity row on nudge?** S22 may write a lightweight activity entry, but the
  unified inbox is W3 (`NOTIFICATIONS.md`) — don't build the inbox here.
- This slice **flips on auto-close** — be deliberate; it's the first time trips
  close without a human in the loop.
