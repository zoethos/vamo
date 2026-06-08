# S40 — Expense category capture (light up the donut + activity icons)

**Branch:** `feature/expense-category-capture` from `main` · **Est:** ~1 dev-day
**Why:** the donut + recent-activity icons are catalog-driven (S35) but the
**add-expense form has no category field** — confirmed: only "Spent in" (currency)
and "Who paid?" (payer) dropdowns exist. So every expense saves `category = null`
→ `CategoryCatalog.resolve(null)` → **"Other" (graphite)** → the donut is always a
black ring and activity icons are always `more_horiz`. The column + repo already
support category (`expenses.category`, `addExpense(input.category)`); only the UI
capture is missing.

## 1. Add a category picker to add-expense
- In `add_expense_screen.dart`, add a **category selector** sourced from
  `CategoryCatalog.canonical` (Food · Lodging · Transport · Activities · Shopping ·
  Other), each shown with its catalog **icon + color** (choice chips read best, or a
  dropdown — chips preferred for one-tap + visual color preview).
- Store the selected **catalog `key`** into the expense `category` (repo already
  writes `input.category`; pass the key through `ExpenseInput`).
- Make it **optional but defaulted sensibly** — if skipped, it stays "Other"
  (don't force it; but offer it prominently so real categories get captured).
- Apply the same picker to the **edit-expense** path so existing expenses can be
  re-categorized.

## 2. Resolve / display
- `CategoryCatalog.resolve` already handles aliases + null→Other; no change needed.
- Donut + activity icons light up automatically once real keys are stored — verify
  a multi-category trip renders multiple colored slices.

## 3. Optional polish (decide)
- "Other" is `graphite` (#2A2E3A) — near-black, especially in dark mode. Consider a
  **lighter neutral grey** for Other so uncategorized spend doesn't read as a black
  void in the donut. Small token tweak in `category_catalog.dart`.
- Optional: a tiny **category icon on each expense row** (Expenses list) for
  consistency with the activity row + donut legend.

## 4. Verification
- `melos run ci`; donut math tests still green.
- Add expenses across ≥2 categories → donut shows ≥2 colored slices summing to the
  total; legend/colors match the catalog; activity rows show the right category icon+color.
- Add an expense with no category → resolves to Other (one slice), and Other reads
  acceptably (not a pure-black void) if §3 applied.
- **On-device** (S25 Ultra): add-expense shows the category picker; pick Food →
  donut slice is orange, activity row shows the orange fork-knife. Light + dark.

## 5. Reviewer checklist
- [ ] Category picker in add-expense (and edit), from `CategoryCatalog.canonical`, icon+color
- [ ] Selected key persisted to `expenses.category` via the existing repo path
- [ ] Donut renders multiple colored slices for a multi-category trip
- [ ] Activity row icons reflect category (not all `more_horiz`)
- [ ] Optional: "Other" recolored off pure-black; expense-row category icon
- [ ] Goldens + donut tests + device pass

## Notes
- This is the missing link that makes the whole S35 category system functional —
  the catalog/donut/activity-icon plumbing already exists and just needs real data.
