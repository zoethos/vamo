# S17 — Trip lifecycle (R3) · implementation prompt

**Branch:** `feature/trip-lifecycle` · **Est:** ~2 dev-days
**Depends:** S16 merged; `fix/join-deeplink-single-handler` merged (push tap safety)
**Spec:** `Vamo_Wave2_Spec.md` R3 · `docs/design/MONEY_GOVERNANCE.md` D2 (amended) ·
`docs/design/CLOSURE_PATTERNS.md` · **diagram contract: `docs/workflows/trip-closure.md`**
**Out of scope (S22/S24):** close report UI, settle nudge copy, retention menus, FCM `UNREGISTERED` pruning, proposal/expense status machine (S19)

> Closure model is **deemed acceptance** (14-day window, silence = consent,
> objection is the only interrupt). The workflow diagram is the contract —
> review against its 8 invariants.

## 1. Migration `0015_trip_lifecycle.sql`

New enum `trip_lifecycle`: `active | cancelled | closing | closed | unresolved`
(CREATE TYPE — safe in one migration; the 55P04 rule only bites ALTER ADD VALUE).

| Table | Columns |
|---|---|
| `trips` | `lifecycle` (default `active`), `closed_at`, `closed_by`, `cancelled_at`, `cancelled_by`, `close_requested_at`, `close_warned_at` |
| `trip_members` | `completed_at`, `close_accepted_at`, `close_objected_at`, `close_objection_reason` |

Helpers (security definer): `is_trip_closed(p_trip)` (`closed|unresolved|cancelled`),
`is_trip_writable(p_trip)` (`active|closing`),
`trip_has_open_close_objection(p_trip)`.

RLS / triggers:
- **Read-only after close:** deny INSERT/UPDATE/DELETE on `expenses`,
  `captures`, `places` (and other member-write tables) when
  `NOT is_trip_writable(trip_id)`. SELECT unchanged.
- **`settlements` is the exception:** writable in `closing`/`closed`/`unresolved`,
  blocked only in `cancelled` (invariant 3 — settling stays open post-close).
- Trips update guard: lifecycle transitions owner-only; co-admin cannot
  cancel/close/force. Members never update lifecycle columns directly.
- `trip_members`: member sets own `completed_at`; own `close_accepted_at` /
  `close_objected_at`+reason only while `closing`.

RPCs (authenticated; revoke/grant pattern as `set_member_role`):
- `request_trip_close(p_trip_id)` — owner, trip `active` → `closing`,
  `close_requested_at = now()`, notify members.
- `mark_trip_member_complete(p_trip_id)` — caller's `completed_at`; if all
  active members complete → auto `closing` (same as request).
- `accept_trip_close(p_trip_id)` — caller's `close_accepted_at`; if all
  active members explicitly accepted → `closed` early.
- `object_to_trip_close(p_trip_id, p_reason)` — reason required; holds
  `closing`. Companion `withdraw_close_objection(p_trip_id)`.
- `force_close_trip(p_trip_id)` — owner; → `closed`; objection rows remain
  untouched (invariant 6).
- `cancel_trip(p_trip_id)` — owner, `active`, `start_date > today()` or null
  → `cancelled`.

## 2. Edge function `trip-lifecycle-jobs` (daily cron)

Deploy `--no-verify-jwt` **but gate every request**:
`req.headers.get("x-cron-secret") !== Deno.env.get("CRON_SECRET") → 401`.
Service role + `record_job_heartbeat('trip-lifecycle-jobs', detail)` per run.
All queries idempotent (invariant 4).

1. **Day-7 reminder:** `closing` AND `close_requested_at + 7d ≤ now()` AND
   `close_warned_at IS NULL` → push, set `close_warned_at`. Once, ever.
2. **Day-14 deemed close:** `closing` AND `close_requested_at + 14d ≤ now()`
   AND no open objection → `closed`, notify (report lists deemed vs explicit).
3. **Month-5 warn / month-6 unresolved:** objected trips only →
   warn, then `unresolved` + `closed_at = now()`, notify, analytics
   `trip_unresolved`.

Secrets: `supabase secrets set CRON_SECRET=…` · extend
`docs/SCHEDULED_JOBS.md` §3 (heartbeat stays bare no-op; real jobs never).

## 3. Flutter UI (minimal, demo-able)

- Member: **"I'm done"** → `mark_trip_member_complete` (confirm dialog).
- `closing` banner: days remaining, **Accept close** / **Object…** (reason
  sheet, required text), objection visible to all members.
- Owner: **Request close** (active), **Close anyway** (typed confirm, only
  shown while an objection is open), **Cancel trip** (pre-start only).
- Read-only chrome when closed/cancelled/unresolved: disable add-expense /
  capture / edits; banner "Trip closed — settling still open" (ARB, i18n).
- Expenses tab: `unresolved` badge in "Earlier" section.
- Analytics: `close_requested`, `close_accepted {explicit|deemed}` (job-side
  for deemed), `close_objected {has_reason}`, `trip_cancelled`,
  `trip_unresolved` — no amounts, no reason text, no tokens.

## 4. `tool/rls_smoke.dart` — new cases (state-based assertions)

| Case | Expect |
|---|---|
| B INSERT/UPDATE expense on closed trip | blocked |
| B INSERT capture on closed trip | blocked |
| B settlement write on closed trip | **ALLOWED** |
| A cancel pre-start; B write on cancelled | cancelled OK; write blocked |
| Deemed close: window expired, B silent | lifecycle = closed |
| B objects; window expires | lifecycle stays closing |
| Co-admin attempts cancel/close/force | blocked |
| C outsider | unchanged deny |

Transitions via RPCs only (use a time-travel knob: allow tests to set
`close_requested_at` back via service role, never via member RLS).

## 5. Tests & CI

- Unit: lifecycle enum parsing, `isTripReadOnly` helper.
- Router: closed-trip deep link opens read-only trip — no GoException.
- `melos run ci` green · `dart run tool/rls_smoke.dart` all PASS.

## 6. RUN.md — Slice 17

Migration push · CRON_SECRET + deploy + dashboard schedule · demo script:
create trip → request close → object → withdraw → accept-all early close →
verify expense write blocked, settlement allowed → force-close path.

## 7. Reviewer checklist

- [ ] Matches `docs/workflows/trip-closure.md` invariants 1–8
- [ ] `x-cron-secret` validated; jobs idempotent
- [ ] `settlements` writable post-close, blocked on cancelled
- [ ] Deemed vs explicit acceptance distinguishable in data (for S22 report)
- [ ] Push routes are in-app paths (`/trips/{id}`), not custom schemes
- [ ] No token/amount/reason text in analytics
- [ ] Co-admin cannot cancel/close (guard + UI hidden)
