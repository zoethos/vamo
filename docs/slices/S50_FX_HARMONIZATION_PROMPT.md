# S50 — Currency control + FX harmonization (Horizon B)

**Why.** Multi-currency trips silently distort the total — the one tab people audit. A number
entered abroad, or a receipt that already printed its own conversion (airport tills, card
terminals), can make "what did this trip cost" wrong, eroding trust. P0 makes each expense's
converted amount **user-correctable and lock-protected**, with **manual override first-class**.

**Scope = P0:** manual per-expense currency + converted-amount override + lock. Receipt-rate
detection is **ADDITIVE (P0.5)** — manual must work with zero OCR. Bulk re-harmonize (P1),
card-statement import + multi-currency settlement (P2) are OUT.

**Money is the trust veto — TESTS FIRST (mandatory, `docs/ARCHITECTURE_BOUNDARIES.md` §11).**
Before touching any conversion/split code: add characterization tests pinning current outputs for
known inputs — exact cents, debtor/creditor ordering, rounding, zero balances, settled offsets,
mixed-currency. Run them GREEN against the current implementation, THEN build behind them.

## A. Schema (migration via `supabase migration new` — current timestamp, not hand-named)
- `expenses`: add
  - `fx_rate_source text not null default 'auto'` (`check (fx_rate_source in ('auto','receipt','manual'))`)
  - `fx_rate_manual numeric`
  - `fx_conversion_locked boolean not null default false`
- RPC `amend_expense_conversion(p_expense_id uuid, p_base_cents bigint, p_source text, p_locked boolean)`,
  `security definer`, **trip-editor only**:
  - auth + editor check; validate `p_base_cents > 0`, `p_source in ('receipt','manual')`;
  - update `expenses.base_cents`, `fx_rate_source`, `fx_conversion_locked` **and re-split
    `expense_shares` atomically**, preserving the **share-sum invariant** (`sum(shares)=base_cents`);
  - **document the deterministic remainder rule** (e.g. first shareholder absorbs the rounding cent);
  - `revoke all on function … from public; grant execute … to authenticated;`
- **Refresh must not clobber edits:** `capture_trip_fx_rate` (and any bulk refresh) must SKIP
  expenses where `fx_conversion_locked` OR `fx_rate_source <> 'auto'` — enforced server-side, so a
  later market-rate refresh never overwrites a manual/receipt amount.

## B. Per-expense override + lock (client) — first-class path
- Add-expense / expense-detail: choosing a foreign currency already exists; add **editing the
  converted (trip-currency) amount**. A manual edit sets `fx_rate_source='manual'` + lock.
- Expenses-tab line: show **original + trip currency**, a **lock badge**, and an edit-converted
  action → `amend_expense_conversion`.
- `expenses_repository.amendExpenseConversion(...)` → RPC; thread `fx_rate_source` +
  `fx_conversion_locked` through models, Drift, and sync (incl. update/reorder payloads — do NOT
  drop the fields on a partial upsert).

## C. Receipt-rate exception — ADDITIVE (may land P0.5, never the only path)
- Extend receipt OCR to detect a printed conversion (foreign total + settlement rate); on add,
  offer "Receipt shows {X} — use this instead of the computed {Y}?" → `source='receipt'` + lock.
  Manual override must function with this entirely absent.

## D. Models / Drift / sync
- `ExpenseSummary` carries `fxRateSource` + `fxConversionLocked`; `LocalExpenses` mirrors the
  columns (Drift `schemaVersion` bump + migration step); `syncExpensesForTrips` selects + stores
  them; update/reorder payloads preserve them.

## E. Tests
- **First** (characterization, per §11): pin `settleUp`, net-balance construction, split rounding,
  FX conversion for known inputs (exact cents) — green on current code before changes.
- amend preserves the share-sum invariant; a **locked expense survives a rate refresh** (server
  skips it); a receipt rate overrides the app rate; deterministic rounding (3-way split pennies
  pinned). New file `fx_harmonization_test.dart`.
- `rls_smoke.dart`: trip-editor can amend; member/outsider cannot; amend on a closed/cancelled
  trip is blocked; a client cannot forge `base_cents`/`fx_rate_source` by writing the row directly
  (bypassing the RPC); a refresh skips locked/amended expenses.

## F. Guardrails / done =
- Manual override is first-class (works with zero OCR); receipt detection additive.
- Deterministic, **documented** rounding; refresh NEVER clobbers a locked/amended line
  (server-enforced); `base_cents` + `expense_shares` update atomically (invariant holds).
- Entry-time FX snapshot remains the shipped model — document it.
- Migration via `supabase migration new`; explicit `revoke`/`grant` on the RPC; if any expense UI
  changes a golden surface, regenerate goldens on **Linux**; watch the `AppColors` ratchet (bump
  `tool/appcolors_baseline.txt` only for legitimately new refs).
- `melos run ci` green; apply the migration to a **NON-prod** Supabase, then `dart run
  tool/rls_smoke.dart` green incl. the amend / lock / refresh-skip cases.

## Notes
- **Branch base:** off `main` only after S47 (#41), S48 (#42), **and S49 (C-light)** are merged —
  B shares `rls_smoke.dart` with all of them and the Drift `schemaVersion` bump path, so an earlier
  base collides (the same trap that hit the S47↔S48 merge).
- Builds on the S20 trip-level constant-rate FX table (`0019/0020`); this adds the per-line
  override/lock layer S20 lacks. Last of the near-term batch (A→J→C-light→**B**).
