# S20 — Money governance II: budget + FX constant-rate table (W2·R6)

**Branch:** `feature/money-governance-ii` · **Est:** ~1.5 dev-days · **Depends:** S19 merged
**Constitution:** `docs/design/MONEY_GOVERNANCE.md` D3 (budget) + D4 (FX) + A3 (typed over-commit)
**Out of scope:** close report (S22), settle nudge (S22), retroactive rate changes (forbidden by D4)

> Carries every pattern now standard: writability-gated writes + restrictive
> DELETE, RPC-only mutations via GUC trigger, ARB strings from the start,
> negative-assertion tests, state-based smoke. No silent English, no hollow tests.

## 1. Migration `0019_budget_and_fx.sql`

**Budget (D3):** trip-level setting, owner/co-admin-managed, visible to all.
- `trips.budget_mode` enum `budget_mode` (`none | informational | formal`),
  default `none`.
- `trips.budget_cents bigint` (nullable; the target in trip base currency).
- Budget + FX writes are gated to `can_edit_trip_content` (owner OR co-admin)
  plus `is_trip_writable`, NOT owner-only. Owner-only remains cancel/delete,
  close lifecycle transitions, and role grants.

**FX constant-rate table (D4):** per-trip captured rates.
- `trip_fx_rates`: `id`, `trip_id`, `currency char(3)`, `rate numeric not null`,
  `source text not null`, `captured_at timestamptz not null default now()`,
  `captured_by uuid fk profiles`. Unique `(trip_id, currency)` — one current
  rate per currency per trip (refresh overwrites the row; history of *expenses*
  keeps their own `fx_rate` snapshot, which is the A4/Wave-1 invariant — the
  table holds the *current* constant rate, not a history).
- **No manual rate entry, ever (D4).** Rate values come only from the market
  reference (existing `fx-rates` server function or a new server-side market
  snapshot). The trusted server path captures; the client never passes a rate
  number.

RLS (all tables): SELECT `is_trip_member`; writes `can_edit_trip_content AND
is_trip_writable`; restrictive DELETE `is_trip_writable`. RPC-only mutation via
a `vamo.fx_rpc` / budget GUC trigger (same pattern as S17/S19).

## 2. Trusted capture path + RPCs

- `set_trip_budget(p_trip_id, p_mode, p_cents)` — `can_edit_trip_content` +
  `is_trip_writable`; validates mode enum; `formal` requires a non-null amount.
- `capture_trip_fx_rate(p_trip_id, p_currency)` or an authenticated Edge
  Function with the same public contract — admin + writable; fetches the market
  rate **server-side** and upserts `(trip_id, currency)` with source +
  captured_by + now(). This is both "add currency" and "refresh".
- Do not pretend the existing Flutter `FxRatesClient` cache is a trusted source:
  the current `fx-rates` Edge Function is trusted server code, but the client
  must never fetch a number and pass it into SQL. If the implementation needs a
  private SQL writer that accepts `rate`, grant it only to service-role / an
  RPC GUC path used by the Edge Function, never to `authenticated`.
- **Refresh-forward-only (D4):** capturing/refreshing a rate affects NEW
  expenses only. Existing expenses keep their stored `fx_rate`. Nothing in this
  RPC touches historical expense rows — assert this in smoke.

## 3. Over-budget flag (A3 — flag, never block)

- A burn-down helper: committed spend vs `budget_cents` (reuse the committed-only
  rule from S19 — proposals don't count against budget until committed; show
  proposed as a separate "if committed" projection if cheap, else omit).
- **`informational`:** show burn-down only.
- **`formal`:** a proposal/commit whose committed total would exceed remaining
  budget is **flagged prominently**, and committing it **requires typed
  confirmation** (A3 teeth — a speed bump, NOT a lock; D2 preserved: commit
  still allowed). The typed-confirm is client-side gating on the commit action;
  the RPC still permits it (never block at the DB — D2).

## 4. Flutter

- Drift v12: trip budget columns, `trip_fx_rates` table; sync handlers.
- Repos: `setTripBudget`, `captureFxRate`; budget burn-down read model.
- UI: trip settings → budget mode + amount (admin only, hidden for members);
  currency/FX management (add currency = capture rate; refresh button per row,
  showing captured_at + source — read-only rate, no text field per D4);
  over-budget flag on proposal/commit with the typed-confirm dialog in formal mode.
- Add-expense currency picker resolves against the trip's constant table; a
  currency not yet present prompts admin "add currency" (capture at market).
- Read-only chrome (S17): budget/FX writes hidden+gated on closed/cancelled.
- ARB strings for everything (parameterized where values interpolate — no
  concatenation); directional.
- Analytics: `rate_refreshed {currency}` (no rate value), budget set event
  (mode only, no amount). No amounts in properties.

## 5. Verification

`tool/rls_smoke.dart` (state-based):
- member cannot set budget / capture rate (role); admin can
- captured rate row appears with source + captured_by; **a second capture
  overwrites the same `(trip,currency)` row** and does NOT alter any existing
  expense's `fx_rate` (the forward-only invariant — assert an expense rate
  before/after refresh is unchanged)
- budget/FX writes blocked on closed + cancelled trips (DELETE too)
- formal over-budget commit still SUCCEEDS at the DB (flag is client-side; D2)

Unit: burn-down math (committed-only); over-budget detection boundary.
Widget (negative assertions, per the CONTRIBUTING rule): budget controls
**absent** for members; FX rate field is **read-only** (no TextField for the
number); formal over-budget commit shows the typed-confirm and does not fire
`action_failed` on success. `melos run ci` green + smoke PASS on cloud.

## 6. RUN.md — Slice 20; **update `docs/workflows/`** if budget/FX deserves a
diagram (D4 forward-only is subtle — a short state note is worth it).

## 7. Reviewer checklist
- [ ] No manual rate entry anywhere — client never sends a rate number (D4)
- [ ] Trusted capture boundary is explicit: client sends only trip + currency;
      any SQL path accepting `rate` is private/service-only
- [ ] Refresh is forward-only: existing expense `fx_rate` untouched (smoke-proven)
- [ ] Budget/FX writes gated to `can_edit_trip_content` + `is_trip_writable`;
      restrictive DELETE present
- [ ] Formal over-budget: typed confirm client-side, DB still permits (D2 — never block)
- [ ] Burn-down counts committed-only (consistent with S19 balances)
- [ ] Zero hardcoded strings; parameterized ARB; negative-assertion tests
- [ ] No amounts/rate values in analytics
