# Money governance — decision memo

## Decision framework (the constitution; test every future case against it)

**VAMO tracks reality, exposes consent, and leaves judgment to the group.**

1. Real money beats planned money: only `committed` expenses affect balances;
   proposals are visible but inert.
2. Consent is annotation, not a gate: accepted/rejected/pending shares inform
   reconciliation but never block deterministic math.
3. Blocking is reserved for lifecycle integrity: cancel, delete, close, and
   archive may require authority or acceptance; ordinary disagreement never blocks.
4. History never drifts: stored FX snapshots, expense records, and rejected
   shares remain auditable forever.
5. Reports resolve ambiguity: disputes, pending proposals, FX drift, and
   unresolved closure are surfaced at close — never auto-corrected.

**Hard display rule (peer to the error-presentation policy):** a disputed or
pending share must NEVER render indistinguishably from an accepted one. The
balance shows "included — disputed by Marco" wherever that share contributes:
balances view, settle-up sheet, close report. Deterministic math + silent
inclusion would be adjudication by stealth; the flag is what keeps the app
honest about its own arithmetic.

Status: **decided 2026-06-05** (founder review of the six questions; this doc
records decisions + the agreed state machine). Feeds the Wave-2 spec session;
implementation in the EventList/TripBoard + money slices.

## D1 — ONE unified lifecycle (founder choice, evaluated: correct)

Two levels, deliberately:

**Expense level** — how money becomes real:
```
            (organizer/co-admin creates planned cost)
  proposed ──────────────► committed ──► [normal settle math]
      │                        ▲
      │ (withdrawn/abandoned)  │ (any member logs a real expense —
      ▼                        │  receipt scan, manual — it is BORN
  cancelled                    │  committed; no ceremony for a coffee)
```
- Only `committed` expenses enter balances/settle-up. `proposed` is visibly
  "not real money yet" (dashed/ghost styling). `cancelled` kept for history.
- Commitment does NOT require unanimity (D2): organizer/co-admin commits
  with responses visible.

**Share level** (per member, on any expense) — how people consent:
```
  pending ──► accepted | rejected(reason, timestamp)
```
- Shares of **born-committed** expenses default to `accepted` (implicit
  consent keeps daily logging frictionless) with a standing right to flip to
  `rejected(reason)` — that IS the dispute, same fields, same UI, no
  parallel machinery.
- Shares of **proposed** expenses are born `pending`; members respond;
  responses inform (not gate) commitment.
- **Rejection never blocks the flow** (D2): rejected shares REMAIN in settle
  math but carry a visible flag; the close-time reconciliation report lists
  every non-accepted share for human resolution. Math stays deterministic;
  judgment stays human.

Why one lifecycle wins (impact eval): one schema (`expenses.status`,
`expense_shares.response/reason/responded_at`), one "respond to this cost"
UI, one analytics family, one reconciliation query at close; dispute =
post-commitment rejection, zero duplicate machinery. Settle engine change is
minimal: filter `status = committed` (today: all rows are committed by
definition) + pass-through flags. Share invariant untouched.

## D2 — consensus, cancellation, closure (founder)

- Anyone can reject/dispute with reason; nothing blocks.
- **Cancel trip** (organizer only, BEFORE start_date): consensus on payments
  failed → whole-trip cancel with notification to all.
- **Close = deemed acceptance** (amended 2026-06-05 per
  `CLOSURE_PATTERNS.md` cross-industry review; supersedes the original
  active-unanimity design): close request (owner, or auto when all members
  mark complete) starts a **14-day window**. Members may explicitly accept
  (all-accept closes early) or **object with reason** — objection is the
  only interrupt; **silence deems acceptance**. The close report lists
  deemed vs. explicit acceptance (consent exposed, never merged). An
  objection holds the trip in `closing` until resolved, withdrawn, or the
  owner force-closes (objection survives into the report, flagged — the
  squeeze-out-with-appraisal-rights pattern). Only objected/stuck trips
  reach **auto-`unresolved` at 6 months**. One reminder at day 7
  (`close_warned_at`, anti-nag). Scheduler: Edge cron (S16 infra) with
  CRON_SECRET. Diagrams: `docs/workflows/trip-closure.md`.

## D3 — roles & budget formality (founder)

- Roles extend to **owner / co-admin / member** (the `role` enum was kept
  extensible for exactly this). Owner: everything incl. cancel/delete and
  role grants. Co-admin: edit trip, create/commit/cancel proposals, manage
  budget + FX table. Member: log own (born-committed) expenses, respond
  accept/reject, view everything.
- Budget mode is a trip setting chosen by the owner and visible to all:
  **informational** (burn-down only) or **formal** (proposals exceeding
  remaining budget are flagged prominently — still not blocked; D2 rules).

## D4 — FX policy: constant market rate, never arbitrary (founder)

- When a currency is added to a trip, its rate is captured from the market
  reference (existing daily-cache infra) and becomes the trip's **constant
  rate** for that currency.
- Admins may **refresh** a rate mid-trip — refresh = re-capture from the
  market reference at that moment. **No manual rate entry, ever** (corporate
  constant-rate practice without the quarterly machinery).
- A refreshed rate applies to **new expenses only**; existing expenses keep
  their stored `fx_rate` snapshots (historical balances never drift —
  Wave-1 invariant preserved).
- Rate rows store: currency, rate, source, captured_at, captured_by.
- OCR continues to accept receipts in ANY detected currency (already true);
  detected currency simply resolves against the trip's constant table, and
  a currency not yet in the table prompts an admin-visible "add currency"
  (captured at market, per above).

## D5 — reconciliation: report-only at close (agreed)

Close-time report (joins the close semantics in WAVE2_PLAN_SEED #10):
constant-rate totals vs market-daily totals (drift, per currency), plus the
consent ledger — every pending/rejected share with reasons. No automatic
adjusting entries. The group reads, talks, and settles like adults.

## Interaction rules (the matrix that bites)

| Case | Rule |
|---|---|
| Dispute after trip closed | Allowed until settlement confirmed; report regenerates |
| Proposal pending at close | Auto-cancelled, listed in report |
| Member silent through close window | Deemed accepted; listed as deemed (not merged with explicit) in report |
| Objection during close window | Holds `closing`; resolve / withdraw / owner force (objection flagged in report) |
| Budget exceeded (formal) | Flag on proposal; commit still allowed (D2) |
| Rate refresh mid-trip | New expenses only; never retroactive |
| Member leaves with rejected shares | Shares remain (debt survives membership); report lists them |
| 6-month unresolved | **Objected/stuck trips only** — auto-close `unresolved`, notify, settle math frozen as-is |

## Amendments (adversarial review, accepted 2026-06-05)

Renamed R# → A# per `docs/CONVENTIONS.md` (R# is reserved for spec
requirements; numbers preserved for traceability).

- **A1 fix (netting)**: settlements are netted and map to no specific
  expense, so the dispute window is **per member**: it closes when that
  member confirms their own settlement after close ("you settled = you
  accepted the math"). Until then, dispute stays open.
- **A3 teeth**: formal budget mode requires typed confirmation to commit an
  over-budget proposal (speed bump, not lock; D2 preserved).
- **A5 consent**: Leave & purge warns when the leaver has unsettled balances
  or open disputes — leaving freezes their responses as-is (RLS makes
  post-leave disputing impossible by design; the warning makes it informed).
- **A6 operations** (amended with deemed acceptance): day-7 single reminder
  during the 14-day close window (`close_warned_at`, anti-nag); the 6-month
  clock starts at close request but only **objected/stuck** trips ride it
  (warn at month 5); unresolved trips remain visible in the Expenses
  "Earlier" section with an `unresolved` badge. All A6/cancel/close
  notifications depend on push plumbing (S16 — shipped).
- **A4 confirmation**: offline expenses snapshot their rate at creation
  on-device (outbox already carries fx_rate), so post-refresh syncs keep
  honest history with no extra work.

## Analytics
`proposal_created/committed/cancelled`, `share_response {response, has_reason}`,
`rate_refreshed {currency}`, `trip_cancelled`, `close_accepted`,
`trip_unresolved`. No amounts, no reasons text in properties.
