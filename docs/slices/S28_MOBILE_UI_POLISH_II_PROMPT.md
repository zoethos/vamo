# S28 — Mobile UI polish II (depth pass)

**Branch:** `feature/ui-polish-2` · **Est:** ~2–3 dev-days · **Depends:** S27 merged; **ideally after S29** (design-system foundation — builds on its tokens/components)
**Why:** S27 did tester-readiness triage; S28 is the *depth* pass — the items
carved out as "Polish II" plus the deferred UX enhancements. Goal: the app reads
as **designed**, not assembled. Subtractive + system-driven (per S29).
**Inputs:** `docs/slices/DEVICE_TEST_FINDINGS.md` (UX enhancements), S27/S29.
**Out of scope:** new features; backend/schema; anything tester-data-dependent
(that waits on the Phase-B gate).

## 0. Foundation note
If **S29** (tokens, type scale, component set) hasn't landed, do its token/type
work *first* or fold it in — S28's screens should consume the system, not
re-introduce hardcoded values. Don't re-create the `goLime`-on-light class of bug.

## 1. Trip tab IA + icons
- Tabs currently truncate ("Expense"/"Member" clipped) and are text-only.
- **Icon + label** tabs: Expense `receipt_long`, Plan `event`/`map`, Balance
  `account_balance`, Members `group`, (Capture `photo_camera`).
- **IA decision (resolve, don't dodge):** is **Capture** a *destination* or an
  *action*? Strong lean: it's an action (scan a receipt) → fold it into the
  add-expense flow / a FAB action and **drop the tab**, reducing 5 tabs → 4.
  Confirm with founder before removing.
- One icon language — don't let trip tabs and the app-level bottom nav diverge.
- A11y labels on every tab.

## 2. Date range picker
- Replace the two separate Start/End fields (trip create + plan-item sheet) with
  a **single range picker**. Zero-dep path: Material `showDateRangePicker`.
- **Must support start-only / no-date** (dates are optional — don't force a
  complete range). Fancier custom/wheel pickers = a deliberate dependency choice,
  not default.

## 3. Money screens — full scan-first redesign
- S27 applied scan-first to Balances at the surface level; S28 does the **depth**:
  Balances + Expenses read as a **statement**, leading with the four questions —
  **who owes whom · what's disputed · what's mine to do · what's final** — then
  detail. Reuse the S22 close-report statement framing for consistency.
- Disputed/objected states must be visually unmistakable (hard display rule:
  disputed never renders like accepted).

## 4. RSVP control finalize
- Land the Material 3 **`SegmentedButton`** for Going/Maybe/Declined (S27 began
  this) — selected fill ink/teal (never lime-on-light), a11y labels, count summary.

## 5. Space-efficiency sweep
- Apply the S27 "compact over chrome" principle across the remaining screens:
  no oversized buttons eating vertical space, dense content-first layouts,
  consistent spacing scale (S29 tokens).

## 6. Verification
- `melos run ci` green.
- **Goldens:** touched screens at Android **small-screen**, **dark mode**, **RTL**.
- **A11y:** `design:accessibility-review` (WCAG contrast) clean — no lime-on-light.
- **On-device pass:** tabs read clean (icons, no clip), range picker works incl.
  start-only, money screens scan-first, RSVP states correct, no overflow.
- Negative-assertion widget tests where behavior changed (e.g. Capture tab
  removed if that decision is taken).

## 7. Reviewer checklist
- [ ] Consumes S29 tokens/type scale; no new hardcoded colors/spacing; no lime-on-light
- [ ] Tabs icon+label, no truncation; Capture tab/action decision made + tested
- [ ] Single date-range picker; start-only/no-date supported
- [ ] Money screens scan-first (who owes / disputed / mine / final); disputed distinct
- [ ] RSVP SegmentedButton finalized (ink/teal selected, a11y)
- [ ] Space-efficiency sweep applied; compact, content-first
- [ ] Golden (small + dark + RTL) + a11y + device pass green

## Notes
- Pairs with **S29** (foundation) — S29 is the substrate, S28 is the screens.
- Anything that needs *tester data* to prioritize is **not** here — it belongs
  after the Phase-B gate (see `docs/WAVE2_GATE.md`).
