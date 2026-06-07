# S22 — Close report + lifecycle nudges + cron enablement (W2·R7)

**Branch:** `feature/close-report` · **Est:** ~2.5–3 dev-days · **Depends:** S17 lifecycle (merged), S16 push (`send-push` working)
**Constitution:** `docs/design/CLOSURE_PATTERNS.md` (deemed acceptance), `MONEY_GOVERNANCE.md` D2 (closure) + **A1** (settlement-confirm closes dispute window), `docs/workflows/expense-consent.md`, `docs/design/NOTIFICATIONS.md` (guardrails), `docs/design/PROVIDER_RESILIENCE.md`
**Out of scope:** unified notifications **inbox** (W3 — S22 is a *producer*); referral; new dispute concepts.

> Makes the S17 closure dance actually fire. `run_trip_lifecycle_jobs()` today
> computes reminders/deemed-close/unresolved **purely on time** and sends
> **nothing**; the cron is unscheduled because of **"no notice, no deemed
> consent."** This slice adds member-scoped notice, anchors the close clock on
> notice, builds the close report, and only then enables the cron.

## ⚠️ The soundness rules (read first — these drove the rewrite)

1. **Notice is PER-MEMBER, not per-trip.** A single `trips.close_notified_at`
   would falsely imply everyone was notified. Track
   **`trip_members.close_notified_at`** (per active member).
2. **The 14-day clock starts at NOTICE, not request.** Existing code uses
   `close_requested_at + 14 days` — wrong if push goes out later via cron.
   Each member's window = **`trip_members.close_notified_at + 14 days`**.
   `close_requested_at` stays for the *state transition / UX* ("closing"
   immediately) but does **not** start the deemed clock.
3. **Deemed-close requires every active member notified-or-acted.** A trip →
   `closed` only when **each active member** has either explicitly acted
   (`close_accepted_at` / `close_objected_at`) **OR** (`close_notified_at` set
   AND their +14d elapsed). A member who was **never notifiable** (no push
   device AND never opened the app to see the in-app notice) **holds the trip
   out of auto-close** → owner force-close, or the existing 6-month
   `unresolved` backstop. That is the whole point of "no notice, no consent."

## 1. What counts as "notice" (member-scoped)
Set `trip_members.close_notified_at` (service-role only) on the **first
successful notice** to that member:
- **Push dispatched** to a registered device (FCM accepted), OR
- **In-app closing notice viewed** — when the member opens the trip in `closing`
  state, stamp `close_notified_at` via a trusted RPC (the act of seeing the
  closing banner is notice). MVP fallback for members without a push device.
- (Email fallback is a later enhancement; not required for MVP.)
No notice channel reached → `close_notified_at` stays null → member is **not**
deemed (rule 3).

## 2. Member-targeted push (the missing capability)
`send-push` pushes only to the **caller's** `push_devices` via their JWT —
unusable from cron. So:
- **Factor the FCM-v1/jose send into a shared helper** reused by both
  `send-push` and `trip-lifecycle-jobs`.
- The cron (service-role) resolves **target members → their `push_devices`**
  server-side and sends via the helper. Client never says who to push.
- **FCM UNREGISTERED / NOT_FOUND → delete that `push_devices` row** in the
  shared helper (S16 pruning, applies to both paths).
- **Resilience** (`PROVIDER_RESILIENCE.md`): handle FCM 429/5xx; one bad token
  must not fail the whole cron run — collect, continue, log counts.

## 3. Notice dispatch + the cron flow
**Single dispatcher = the cron** (robust, no reliance on client being online
post-request; naturally notice-anchors the clock):
- `request_trip_close` (SQL RPC) only sets `lifecycle='closing'` +
  `close_requested_at` — it **cannot** send FCM.
- The cron picks up `closing` trips with **un-notified active members**,
  dispatches the per-member close notice, stamps `close_notified_at`.
- *(Optional latency enhancement, not required:* a DB-trigger→`pg_net`→edge, or
  the client calling a service edge fn right after `request_trip_close`, to send
  the first notice immediately — still stamping `close_notified_at`.)*

Cron moments (extend `run_trip_lifecycle_jobs`, don't rebuild):

| Moment | Per-member condition | Copy (route → trip / close report) |
|---|---|---|
| **Close notice** | `closing` + member `close_notified_at` null | "Trip is closing — review. Auto-closes 14 days after you're notified." |
| **Day-7 reminder** | `now ≥ close_notified_at + 7d`, not acted, single-shot | "**7 days left** to review *<trip>* before it closes." |
| **Deemed closed** | trip → `closed` (rule 3 satisfied) | "Trip closed. Settle up when ready." |
| **Settle nudge** | member has outstanding settlement | "You still have a balance to settle in *<trip>*." (no amount on lock screen) |

- **Anti-spam, per member, single-shot:** day-7 uses a member-level marker;
  settle nudge uses **`trip_members.settle_nudged_at`** (or a tiny nudge log) so
  the daily cron can't re-spam. (Trip-level `close_warned_at` no longer
  sufficient — must be member-scoped.)
- **NOTIFICATIONS.md guardrails:** sparse, personal, actionable; money/dispute
  is **lock-screen-sensitive** (title only, no amounts/balances); deep-link
  `route`; ops alerts separate.

## 4. A1 — settlement-confirm closes the dispute window (IN SCOPE)
`expense-consent.md` lands this cutoff with S22. Today `respond_to_share`
(dispute/reject) stays open after close/unresolved with no cutoff.
- **Enforce:** once a member **confirms their own settlement**, their dispute
  window closes — `respond_to_share` (reject/dispute) is **blocked for that
  member** thereafter (A1: "you settled = you accepted the math"; the
  construction "final certificate" per member).
- Add the guard in `respond_to_share` + smoke (settle-then-dispute blocked;
  dispute-before-settle still allowed on closed/unresolved).
- *(If S22 is getting too big, this is the one piece that can be carved into a
  fast-follow — but it's coherent with close-finality, so default IN.)*

## 5. New columns MUST be guarded
Adding `trip_members.close_notified_at`, member-level day-7 marker, and
`settle_nudged_at` means these are **service-role/cron-only** — never
client/owner/co-admin writable. Update **all** of:
- `trips_lifecycle_guard`, `trips_update_guard`, `trip_members_lifecycle_guard`
  (block direct mutation of notice/nudge state; allow only the GUC/service path).
- Drift schema (v14) + **migration tests**.
Otherwise an owner/co-admin/client update could forge notice state and trigger a
deemed-close. Treat these columns like the lifecycle timestamps they are.

## 6. Close report (the "statement")
- **Read model** for `closing`/`closed`/`unresolved`: final per-member balances
  (committed-only, consistent with S19/S20), who **accepted explicitly** vs
  **deemed** (`close_notified_at`+window, no explicit act) vs **objected**
  (CLOSURE_PATTERNS "deemed ≠ hidden"), and **disputed shares flagged** (hard
  display rule — disputed never renders like accepted; force-close objections
  surface as "included — objected by X", the squeeze-out/appraisal pattern).
- **Snapshot vs live:** MVP computes live; immutable snapshot at deemed-close is
  cleaner long-term — flag, don't build now unless cheap.
- UI: Close report screen reachable from the trip + the notice deep-link;
  read-only chrome per S17 (settlements still allowed per A1).
- No amounts in analytics; ARB parameterized; directional.

## 7. Cron enablement (LAST) + Deno hygiene
- Schedule `trip-lifecycle-jobs` **daily** (Supabase Cron, `x-cron-secret`)
  **only after** the nudge path is device-verified. Document the exact entry in
  `SCHEDULED_JOBS.md`. Enabling it is what flips on auto-close.
- **Touched edge functions** (shared FCM helper, `trip-lifecycle-jobs`,
  `send-push`): per §2.1 of `SECURITY_PATCHING.md` — function-local `deno.json`,
  committed **frozen `deno.lock`**, `deno check` in CI, **no raw imports**.

## 8. Verification
`tool/rls_smoke.dart` (service-role for the job path):
- per-member: a `closing` trip with one **un-notified** active member does **NOT**
  deem-close even past 14d; once that member is notified, window starts from
  **their** `close_notified_at`.
- deemed-close fires only when every active member acted-or-(notified+14d).
- day-7 reminder single-shot per member (not re-sent on a second run).
- **settle nudge** single-shot per member (`settle_nudged_at`).
- **A1:** member who confirmed settlement cannot `respond_to_share`; one who
  hasn't still can (on closed/unresolved).
- guards: client/owner/co-admin cannot write `close_notified_at` / nudge markers.
- close report: deemed vs accepted vs objected distinct; disputed never as
  accepted; balances committed-only. Settlements writable on `closed`, blocked
  on `cancelled` (S17 regression guard).

Unit/widget (negative assertions): report renders the three consent states +
disputed distinctly; push payload has no amounts in lock-screen-visible fields.

**Device + cron gate (CI/smoke can't see push/cron):**
- S25: close a trip → **per-member push arrives on a 2nd member's device** →
  tap routes to the close report.
- **Manually invoke** `trip-lifecycle-jobs` with `CRON_SECRET` (dry-run on a test
  trip past a member's day-7) → reminder arrives, member marker set, no re-spam
  on a second invoke.
- Then enable the daily cron; confirm next tick's `job_heartbeats` row.

`melos run ci` green + smoke PASS + the device/cron gate.

## 9. Reviewer checklist
- [ ] Notice is **per-member** (`trip_members.close_notified_at`), not trip-level
- [ ] Close clock anchored on **notice** (`close_notified_at + 14d`), not request
- [ ] Deemed-close requires **every** active member acted-or-(notified+window); never-notified members hold the trip out of auto-close
- [ ] First notice dispatch path is explicit (cron picks up un-notified closing trips); `request_trip_close` doesn't (can't) push
- [ ] Member-targeted push is service-role/server-resolved; FCM UNREGISTERED pruned; 429/5xx don't fail the run
- [ ] Day-7 + settle nudges **per-member single-shot** (anti-spam markers)
- [ ] New notice/nudge columns guarded in trips_lifecycle_guard / trips_update_guard / trip_members_lifecycle_guard + Drift migration tests
- [ ] **A1 cutoff** implemented (settle-confirm blocks further dispute) or explicitly deferred with sign-off
- [ ] Close report: deemed/accepted/objected distinct; disputed never as accepted; committed-only balances
- [ ] Touched edge fns: frozen `deno.lock` + `deno check` + no raw imports
- [ ] NOTIFICATIONS guardrails (no amounts on lock screen; sparse; deep-link)
- [ ] Cron scheduled only after device-verified nudges; exact entry in SCHEDULED_JOBS.md
- [ ] Copy fixed: day-7 = "**7 days left**" (not 5); zero hardcoded strings; no amounts/PII in analytics
- [ ] Device + 2-device + cron-dry-run gate passed before merge

## Notes / decisions
- **Snapshot vs live close report** — MVP live; snapshot later (founder call).
- **A1 cutoff** — default IN scope; carve to fast-follow only if S22 over-grows.
- This slice **flips on auto-close** — first time trips close without a human in
  the loop; the heavier gate is deliberate.
