# S19 — Money governance I: states + responses + display rule (W2·R5)

**Branch:** `feature/money-governance-i` · **Est:** ~2.5 dev-days · **Depends:** S18 merged
**Constitution:** `docs/design/MONEY_GOVERNANCE.md` D1 + A1 · **Contract:** `docs/workflows/expense-consent.md`
**Out of scope (S20/S22):** budget + FX table (S20), close report rendering (S22), settle nudge (S22)

> Read `docs/workflows/expense-consent.md` first. The two invariants there are
> the whole point of this slice — the reviewer checklist tests them directly.

## 1. Migration `0017_expense_status_and_share_response.sql`

Two enums (CREATE TYPE — safe single migration):
- `expense_status`: `proposed | committed | cancelled`
- `share_response`: `pending | accepted | rejected`

Columns:
- `expenses.status expense_status not null default 'committed'`
  (default = born-committed; backfills every existing row correctly — they
  ARE committed by definition)
- `expense_shares.response share_response not null default 'accepted'`
  (backfill: existing shares are accepted)
- `expense_shares.response_reason text`
- `expense_shares.responded_at timestamptz`

**Rewrite `trip_balances`** (INVARIANT 1 — the critical change):
- `paid` CTE: `where status = 'committed'`
- `owed` CTE: join expenses, `where e.status = 'committed'` — **do NOT filter
  on `s.response`**. Rejected shares stay in `owed`. Only expense status
  filters; `proposed`/`cancelled` leave the math, response never does.
- settlements CTEs unchanged.
- Keep `security_invoker = on` (0007).

## 2. RPCs (authenticated; revoke public, grant authenticated)

Expense-status transitions — **owner/co-admin only, `is_trip_writable` gated**:
- `propose_expense(...)` — inserts `status='proposed'` AND **creates the full
  share set** for the trip's active members, each born `pending`, with
  `sum(share_cents) == base_cents` (same split invariant as committed
  expenses — do not leave shares to a second call). A proposed→committed
  transition must therefore already satisfy the share invariant; add a
  unit + smoke case asserting it.
- `commit_expense(p_expense_id)` — `proposed→committed`; role + writable checks;
  shares stay as members left them (pending stays pending until they respond).
- `void_expense(p_expense_id)` — `→cancelled`; role + writable.

Share response — **any active member, own share only, NOT writability-gated**
(INVARIANT 2 — allowed in closed/closing/unresolved, blocked only in cancelled):
- `respond_to_share(p_expense_id, p_accept bool, p_reason text)` — **UPDATEs
  the caller's existing own share row only** (never creates one — a missing
  row means a proposal/share-construction bug, must error, not paper over).
  Require exactly one `(expense_id, auth.uid())` share row; set `response`,
  `responded_at`; reject requires non-empty `response_reason`; **accept clears
  `response_reason`**. Guard: trip not `cancelled`; caller is active member.
- **RLS escape mechanism (be explicit — 0015 `shares_all` is writability-gated):**
  add a GUC-gated trigger like S17 (`vamo.share_rpc` flag set inside this RPC)
  that permits the response-field update through; OR a narrowly-scoped
  restrictive policy allowing UPDATE of ONLY `response/response_reason/
  responded_at` by the owning member when trip is not cancelled. Do not widen
  the existing writability gate for the rest of the expense_shares row.

Born-committed path (existing add-expense flow) is unchanged behaviorally —
it writes `status='committed'` (the default) and the payer's own share
`accepted`; co-participants' shares default `accepted` too (implicit consent,
D1). No new RPC; the default columns handle it.

## 3. RLS

- Expense status columns: only the role-checked RPCs flip them; a plain member
  UPDATE that touches `status` must fail (guard trigger, GUC-gated like S17, OR
  rely on RPC-only by revoking column update — pick the S17 pattern: trigger
  checking `vamo.expense_rpc` flag).
- `expense_shares.response/reason/responded_at`: writable by the owning member
  via the RPC; **not** gated by `is_trip_writable` (A1). Block in `cancelled`.
- Existing expense INSERT/UPDATE writability gate (S17) stays for the expense
  body; do not regress it.

## 4. Flutter

- Drift v11: expense `status`, share `response/reason/respondedAt`; sync handlers.
- `ExpensesRepository`: propose/commit/void + respondToShare.
- **Local balances do NOT update for free** (P1 — the UI reads the Drift
  recompute in `balances/balances_repository.dart`, not the server view):
  - `_compute` must filter `LocalExpenses.status == 'committed'` (mirror
    INVARIANT 1 exactly — committed-only expenses; **all** their shares
    regardless of response; rejected shares still count).
  - `watchTripBalances` currently subscribes to expenses + settlements only;
    **add an `expense_shares` watch** so disputed/pending badges refresh when
    only a share `response` changes.
- UI:
  - Proposed expenses render ghost/dashed (D1), with Commit/Void for admins.
  - Per-share response control on expense detail: Accept / Dispute (reason sheet).
  - **Hard display rule**: balances rows, settle-up sheet, and expense rows
    show "included — disputed by <name>" wherever a non-accepted share
    contributes. A pending/rejected share must never look accepted.
- Read-only chrome (S17): propose/commit/void disabled when not writable;
  **dispute stays enabled after close** (until own settle-confirm) — this is
  the one control that survives close.
- ARB strings; directional; analytics `proposal_created/committed/cancelled`,
  `share_response {response, has_reason}` — no amounts, no reason text.

## 5. Verification — `tool/rls_smoke.dart` (all state-based)

Per the contract's case list:
- proposed expense leaves `net_cents` unchanged; commit changes it
- reject vs accept on a committed share → **same** `net_cents` (rejected still counts)
- cancelled expense leaves the math
- member disputes own share on CLOSED trip → ALLOWED; on CANCELLED → blocked
- member cannot respond to another's share
- plain member cannot commit a proposed expense (role)
- born-committed expense: shares default accepted

Plus: unit tests (state machine transitions, balance recompute with a rejected
share present), widget test (disputed badge renders; proposed ghost styling),
drift v10→v11. `melos run ci` green + smoke full PASS on cloud.

## 6. RUN.md — Slice 19; update `docs/workflows/expense-consent.md` if design shifts.

## 7. Reviewer checklist (the invariants)

- [ ] `trip_balances` filters on expense `status='committed'`, NEVER on share response
- [ ] A rejected share still contributes to `owed` (verified by equal-net smoke case)
- [ ] `respond_to_share` works on a closed trip; blocked only on cancelled
- [ ] Expense status transitions are role-gated AND writability-gated
- [ ] Hard display rule present in balances + settle sheet + expense row
- [ ] No amounts / reason text in analytics
- [ ] Drift migration covers existing rows (default committed/accepted)
- [ ] Local Drift balance computation filters `LocalExpenses.status == committed`
      and never filters by share response
- [ ] Balance/dispute UI watches `expense_shares` response changes, not only
      expense/settlement changes
- [ ] `respond_to_share` updates an existing own share only; never creates
      share rows; clears `response_reason` on accept
- [ ] `propose_expense` creates the full share set with `sum(share_cents)
      == base_cents`; smoke asserts proposed→committed preserves it

## 7b. Second-review fixes (required before merge)

- **Smoke (failure 2 cause):** the cancelled-dispute case disputes a share on
  the *closed* trip's expense (correctly allowed) instead of one in the
  cancelled trip. Create an expense + caller share INSIDE `cancelTripId`,
  cancel, then dispute THAT → expect blocked.
- **Smoke (failure 1):** run the void case on a writable (active) trip so
  `void_expense` isn't rejected by the read-only gate; assert net restores.
- **Forged-dispute guard (integrity P1):** `expense_shares_response_guard`
  currently blocks only non-RPC `pending` inserts. Tighten: a non-RPC INSERT
  must be exactly `accepted` / null reason / null `responded_at`; `pending`
  only under the propose flag; `rejected`/reason/responded_at on insert →
  raise. Add the smoke case. (Contract integrity rule 3.)
- **Realtime gap (P1):** `expense_shares` is not in the realtime subscription
  set (`trip_realtime.dart`), so a dispute never reaches other devices. Fix
  via membership-filtered `expense_shares` subscription OR have
  `respond_to_share` touch the parent `expenses` row so the existing
  subscription fires (likely simpler given realtime's joined-table filter
  limits). (Contract integrity rule 4.)
- **Online-only governance (P2 — document, don't silently claim "sync"):**
  propose/commit/void/respond are direct RPC calls with no outbox `SyncKind`.
  That's acceptable for S19 (deliberate acts, not frictionless logging), but
  state it explicitly in RUN.md; born-committed expense logging stays
  offline-first as before.

## 8. Explicitly deferred (do NOT let S19 claim these)

- **Settlement-confirm dispute gating (A1's "until own settle-confirm").**
  S19 guards `respond_to_share` on `not cancelled` + active member + own share.
  It does NOT yet block disputes after a member confirms their settlement —
  because "what counts as confirming your own settlement" needs the S22
  settle-confirm flow to be defined. Mark this gate as **S22**; soften any
  wording that implies S19 fully closes the per-member window. Workflow doc
  updated to match.
- **Debt survives membership.** `trip_balances` (and the local recompute) select
  `status = 'active'` members only, so a left member's debt drops out of the
  balance view. The constitution's matrix row ("Member leaves with rejected
  shares — debt survives membership; report lists them") is satisfied by the
  **close report (S22)**, not S19. Do not change the balance view's
  active-only filter in S19; flag for S22.
