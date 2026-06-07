# Device-test findings (manual, S25 + Chrome) — UI/nav polish

Found during the S21 two-user realtime test (2026-06-06). These are
**app-shell / nav / UX** issues, distinct from S21's RSVP-realtime logic
(which is smoke-verified 76/76). Treat as a UI-polish batch for Cursor —
fix before internal testers, but not an S21-merge blocker unless noted.

| # | Finding | Where | Scope | Severity |
|---|---|---|---|---|
| 1 | ✅ **FIXED** — back button falls back to trips list when no pop stack (deep-link/reload safe); regression test added. Original finding: no Android back affordance on mobile detail screens. | trip_home_screen.dart | done | High |
| 2 | ✅ **FIXED** — tab-aware FAB (Plan → add item, Expense → add expense, hidden on Balance/Members/Capture) + duplicate Plan CTA removed in trip-home context; regression test added. Original finding: fixed add-expense FAB ignored active tab. | trip tab scaffold / FAB, plan_tab.dart | done | Medium |
| 3 | **Lime on white is unreadable — RECURRING.** `goLime #C6FF00` used as foreground/text on a white surface fails contrast. Brand rule (DESIGN_BRIEF): goLime is an **accent for Ink text only — never text/foreground on light**. This was flagged before and regressed. | audit all `goLime` usages on light backgrounds | Cross-cutting (brand/a11y) | High (readability) |

| 4 | **Type dropdown mislabeled "Title".** Options DO exist (lodging/flight/train/activity/other) — pick "activity" to make an event. Only the label is wrong ("Title" → "Type/Kind"). Feature is reachable; this is polish. | Add plan item sheet | S21/S18 UX | Medium |
| 10 | **Web join — UNCONFIRMED.** The trip didn't show for zoethos, but the invite was pasted while Chrome was logged in as **tiziano** (self-join = no-op), and we then added the membership via SQL instead of re-testing as zoethos. So the web join flow is **not confirmed broken** — needs a clean test: Chrome logged in as zoethos → paste invite → verify `trip_members`. | invites/join flow (web) | Needs clean retest (not S21) | TBD |
| 12 | **Members view: duplicate "Invite Amigos" buttons** (top + bottom) + "Show QR", all oversized — redundant, wastes vertical space. | Members tab | UI defect + design | Medium |
| 11 | **Trips list doesn't pick up a new membership without a full reload.** After server-side membership add, the trip only appeared in Chrome after a hard browser refresh — no in-app/realtime refresh of the trips list. | trips list sync | Separate bug (not S21). | Medium |
| 5 | **Event type not visible from within the event.** If an item is an activity/event, it should be identifiable inside the event view (a label/badge in a corner). | event detail | S21 UX | Low |
| 8 | **Duplicate "Title" labels in Add plan item sheet.** The **type dropdown** and the **title text field** are both labeled "Title". Dropdown label should be "Type"/"Kind". | Add plan item sheet | S18/S21 UI | Medium |
| 9 | **Add plan item sheet overflows when keyboard opens (RenderFlex "BOTTOM OVERFLOWED BY 137px").** Content isn't scrollable and doesn't account for the keyboard inset → form unusable with keyboard up; Save/date fields unreachable. Also collides with the system nav bar without the keyboard. **Fix:** wrap body in `SingleChildScrollView`, show the sheet `isScrollControlled: true` with `padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom)` + `SafeArea`. | Add plan item sheet (audit other bottom sheets too) | Pre-existing layout (keyboard inset / safe area) | High |
| 3a | **Lime label confirmed:** the "Title" field label renders in `goLime` on the light sheet — unreadable. Concrete instance of #3. | Add plan item sheet | brand/a11y | — |

| 6 | **No "Resend code" on the OTP verify screen → sign-in dead-end.** When the code expires, the only option is "use a different email" (wrong when the email is correct). User is stuck on Verify & Continue. | auth / OTP verify screen | Pre-existing auth flow. **High** — every tester with a slow inbox hits this. | High |
| 7 | **Raw error codes leaked to the user** ("code did not match try again (otp_expired)") — unpolished, and violates the project error policy (catalogued user messages only, no vendor/exception leakage). | auth / OTP verify error states | Pre-existing; **regression vs error policy**. | Medium |

> **Process note:** smoke verifies data/RLS only — it does **not** test Flutter
> UI. A green smoke is necessary but NOT sufficient; UI affordances need an
> on-device check (this pass). Don't treat a Cursor "shipped" report as verified
> UI until seen running.

## UX enhancements (not defects — design pass, post-merge)

- **Consolidate invites into one compact action.** Replace the duplicate
  "Invite Amigos" + "Show QR" buttons (#12) with a single **"Invite Vamigos"**
  entry → small sheet with channels: copy link / show QR / from contacts (S26
  plugs in here as an option, not a new button).
- **Space-efficiency principle (design pass):** stop spending vertical space on
  oversized buttons; prefer compact, dense, content-first layouts. More room for
  features, not chrome.
- **Trip tabs → icon + label (labels truncate today).** Expense `receipt_long`,
  Plan `event`/`map`, Balance `account_balance`, Capture `photo_camera`, Members
  `group`. Consider whether **Capture** is an action, not a tab (reduce tab count).
  Keep one icon language vs the app-level bottom nav. A11y labels required.
- **RSVP control → Material 3 single-select `SegmentedButton`.** Replace the three
  full-width Going/Maybe/Declined text chips with one connected segmented bar,
  icon + label (Going ✓ `check`, Maybe ? `help_outline`/`schedule`, Declined ✕
  `close`). More compact + idiomatic Android. Keep the count summary. A11y:
  semantic labels per segment (esp. if icon-only). Contrast: selected fill must
  NOT be lime-on-white (see #3) — use Ink/teal.
- **Date range picker.** Replace the two separate Start/End date fields (trip
  create + plan-item sheet) with a **single range picker**. Zero-dep path:
  Material `showDateRangePicker`. Fancier custom/radial controls = a deliberate
  design-pass choice (weigh the added dependency vs the register). Must still
  support **start-only / no-date** (dates are optional).

## Remaining fix order for the next mobile pass

1. **P0 — sign-in dead-end (blocks every tester):** #6 add "Resend code" on OTP
   verify; #7 replace raw error codes with catalogued messages.
2. **P1 — create-event usable:** #4 relabel type dropdown
   "Type/Kind"; #8 fix duplicate "Title" labels; #9 make the Add plan item sheet
   keyboard-safe (scroll + viewInsets + SafeArea); then confirm the
   Going/Maybe/Declined chips render on activity cards.
3. **P1 — contrast:** #3/#3a lime-on-light audit + token annotation.
4. **P2 — polish + retest:** #5 event-type badge inside the event; #10 clean web
   join retest as a second user; #11 trips-list refresh after join; #12 compact
   the invite surface.

After the remaining batch lands → one clean device pass should verify tester
readiness across auth, plan-item creation, join refresh, and invite chrome.

## Stop the lime recurrence (it's regressed before)
Re-fixing #3 by hand will just let it come back. Make it structurally hard:
- **Audit + fix** every `goLime` used as text/icon/foreground on a light surface
  (replace with Ink/coral/plum; keep goLime only as a dark-surface accent or a
  tinted background behind Ink).
- **Annotate the token** at its definition (`AppColors.goLime`) with the usage
  constraint so it's visible at the call site: *accent on Ink/dark only — never
  foreground on light.*
- **Run an accessibility/contrast pass** on the key screens before internal
  testers (the `design:accessibility-review` skill covers WCAG contrast).

## Notes
- #1/#2 are fixed by the S27 polish stack; keep the rows as regression memory.
- Remaining mobile-vs-web parity issues should be verified on device, not only
  through Flutter tests or Chrome.
