# S19.1 — Money governance finish: propose-expense UI + governance i18n (W2·R5)

**Branch:** `feature/governance-ui-i18n` · **Est:** ~1 dev-day · **Depends:** S19 merged
**Gates:** the S15–S17 internal build (R5 is untestable in the field without a way to *create* a proposal; governance strings must not ship hardcoded English to multi-locale testers)
**No migration, no schema** — `propose_expense` RPC and proposed/ghost rendering already exist (S19). This slice is UI + strings only.

## 1. Propose-expense UI (the missing birth path)

Today `propose_expense` exists but nothing calls it; only the existing
add-expense flow (born-committed) reaches the DB. Add the proposal path:

- **Entry point:** on the trip's expenses area, an admin-only **"Propose a
  cost"** action (owner/co-admin — gate on the same `can_edit_trip_content`
  capability the RPC enforces; hide for plain members, don't just disable).
  Reuse `AddExpenseScreen` with a `mode` (committed vs proposed) rather than
  forking a second screen — same fields (amount, currency, description,
  category, payer, split), one flag that routes save to `propose_expense`
  vs the existing committed insert.
- **Split:** proposals create the full active-member share set (the RPC does
  this server-side). The form's split UI is the same as committed expenses;
  do not invent a parallel splitter.
- After propose: land back on the expenses list where the row already renders
  ghost/dashed (S19) with the existing Commit/Void admin controls in the
  detail sheet. No new detail UI needed — just make sure a freshly proposed
  item is reachable and shows pending shares.
- Read-only chrome (S17): the Propose action is `is_trip_writable`-gated like
  other writes — hidden/disabled on closed/cancelled/unresolved trips.
- Analytics: `proposal_created` already defined — fire it on success (no
  amount, no description text).

## 2. Governance i18n (clear the ARB debt before it compounds)

S19 shipped governance strings hardcoded in English. Move them all to ARB via
the existing labels-bundle pattern (`split_labels.dart` + `AppLocalizations`,
same shape as `PlanTabLabels`):

- Sweep these files for literal user-facing strings: `expense_governance.dart`
  (incl. the hard-display-rule `'included — disputed by <name>'` at line ~57),
  `expense_detail_sheet.dart`, `expense_consent_providers.dart`, and the new
  propose-UI strings.
- Add an `ExpenseGovernanceLabels` bundle (mirror `PlanTabLabels`); source it
  from `AppLocalizations` in `split_labels.dart`; thread through widgets.
- The disputed-by string is a **parameterized** ARB entry
  (`includedDisputedBy(name)` with placeholder), not concatenation — RTL +
  script-correctness rule.
- Add keys to `app_en.arb`; other locales fall back per existing i18n hygiene
  (untranslated keys are acceptable; hardcoded English in widgets is not).
- Verify directional layout for the new propose form (mirror-ready).

## 3. Verification

- Widget tests: admin sees "Propose a cost", plain member does not; proposed
  save calls `propose_expense` (mock/repo assertion) and renders ghost;
  disputed badge text comes from the labels bundle, not a literal.
- i18n: the existing RTL golden / script smoke tests extend to a governance
  surface (detail sheet or proposed row) so a hardcoded string would fail.
- `melos run ci` green. **No `rls_smoke` change** (no DB delta) — but do a
  manual cloud sanity: propose → commit → balances move; propose → void →
  balances unchanged.
- Manual (device, with the S16 rebuild): second device sees a proposed item
  and a dispute badge appear (closes the realtime parent-touch verification
  that smoke can't cover).

## 4. RUN.md — note the propose flow in the Slice 19 section (online-only RPC).

## 5b. Second-review fixes (required before merge)

- **Hide receipt/OCR/place block in `AddExpenseMode.proposed`** — `proposeExpense`
  drops that data, so showing the capture UI is silent data loss. Proposals =
  amount + description + split only. (Proposal evidence = deferred spec P2
  `attachment_path`; do not build now, just don't show inputs that vanish.)
- **Screen-level guard on the propose route** — `/trips/:id/expenses/propose`
  is deep-linkable; the hidden button isn't enough. `AddExpenseScreen` in
  proposed mode must check role (owner/co-admin) + `is_trip_writable` and
  bounce non-admins / closed trips before rendering the form, not rely on the
  RPC rejection. Add member + closed-trip router/widget tests.
- **Real role-gate UI test** — render `_ExpensesTab` and assert the propose
  action is absent for a member / present for an admin; the current test only
  asserts `canEditTripProposals()` (a helper, not the UI).
- **Fix the false-positive proposed-save test** — it passes while logging
  `action_failed` because `context.pop()` throws in the `MaterialApp` harness
  and the catch swallows it. Use a GoRouter/Navigator harness; assert the
  error path does NOT fire on success.
- **Remove hardcoded `"Proposal"` fallback** (`trip_expense_list_tile.dart`):
  make the label required so English can't silently reappear.

## 5. Reviewer checklist

- [ ] Propose action gated to owner/co-admin (hidden for members) AND
      `is_trip_writable` (hidden when closed/cancelled)
- [ ] Reuses AddExpenseScreen via a mode flag — no forked screen, no parallel splitter
- [ ] Zero user-facing hardcoded strings remain in the governance files
- [ ] `includedDisputedBy` is a parameterized ARB entry, not concatenation
- [ ] proposal_created fires with no amount/description in properties
- [ ] An i18n test covers a governance surface (catches future hardcoding)
