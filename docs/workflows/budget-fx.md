# Budget + FX constant-rate workflow (S20 / D3 · D4 · A3)

## Budget (D3)

- Trip setting: `none` | `informational` | `formal`, stored as `trips.budget_mode` + `budget_cents`.
- Owner **or co-admin** may set; all members see burn-down when mode is informational/formal.
- Burn-down uses **committed** expenses only (same rule as S19 balances — proposals do not count until committed).
- **Formal** mode: UI flags over-budget proposals/commits and requires **typed confirmation** before commit (A3). The DB **never blocks** the commit (D2).

## FX constant-rate table (D4)

```
Admin captures/refresh ──► trip_fx_rates (one row per trip+currency)
                                    │
                                    ▼
              New expense/proposal reads rate ──► expenses.fx_rate snapshot
                                    │
              Refresh does NOT update ◄────────── existing expense rows
```

- **No manual rate entry.** Client calls `capture_trip_fx_rate(trip_id, currency)` only; server fetches market reference and upserts.
- Private SQL paths that accept a numeric `rate` are **not** granted to `authenticated`.
- Refresh overwrites `(trip_id, currency)` in `trip_fx_rates` but leaves every existing `expenses.fx_rate` unchanged — assert before/after in `tool/rls_smoke.dart`.

## Writability

Budget + FX writes require `can_edit_trip_content` **and** `is_trip_writable` (active/closing). Closed and cancelled trips block RPCs and direct table writes; restrictive DELETE on `trip_fx_rates` mirrors S17 patterns.

## rls_smoke cases (state-based)

- Member cannot `set_trip_budget` / `capture_trip_fx_rate`; owner can.
- Captured row has `source` + `captured_by`; second capture same currency overwrites one row; anchor expense `fx_rate` identical after refresh.
- Budget/FX RPCs fail on closed + cancelled trips.
- Formal over-budget `commit_expense` **succeeds** at the DB (flag is client-only).
