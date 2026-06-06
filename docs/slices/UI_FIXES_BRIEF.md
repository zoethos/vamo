# UI fixes batch — device-test findings → implementation brief

Source: `docs/slices/DEVICE_TEST_FINDINGS.md` (manual S25 + Chrome pass, 2026-06-06).
All **UI/auth/layout** — no schema/RPC changes. Suggested branch
`fix/ui-device-batch`, committed in the priority groups below. Each fix is
**verified on device** (the smoke can't see UI). Run `melos run ci` green before PR.

---

## P0 — Sign-in is a dead-end (blocks every tester)

### #6 — Add "Resend code" to the OTP verify screen
- On the OTP verify screen (feature_split auth / verify-OTP widget), add a
  **"Send me a new code"** action.
- Wire it to the same `signInWithOtp(email)` path used to send the first code.
- Add a **cooldown** (e.g. 30–60s countdown, button disabled meanwhile) to
  prevent spamming and the "older code invalidates newer" confusion.
- Keep "use a different email" as a secondary action, not the only escape.
- **Accept:** an expired/lost code is recoverable from this screen without
  changing email.

### #7 — Catalogued error messages (no raw codes)
- Replace surfaced raw errors (`otp_expired`, "code did not match try again")
  with **catalogued user messages** via the existing `showActionError` path
  (project rule: catalogued only, no vendor/exception leakage).
- Map: expired → "That code expired — tap *Send me a new code*."
  mismatch → "That code didn't match — check it and re-enter, or resend."
- **Accept:** no error code or raw provider string ever reaches the UI.

---

## P1 — S21 create-event usable (gates S21 merge)

### #4 + #8 — Fix the Add plan item labels
- The **type dropdown** is labeled "Title"; relabel to **"Type"** (ARB string).
- The **title text field** is also labeled "Title" — keep that one "Title".
  (Two "Title" labels today; after fix: "Type" + "Title".)
- **Accept:** the dropdown reads "Type"; options remain
  lodging/flight/train/activity/other.

### #9 — Add plan item sheet: keyboard overflow + safe area
- Body overflows ("BOTTOM OVERFLOWED BY 137px") when the keyboard opens, and
  Save collides with the system nav bar.
- Wrap the sheet body in **`SingleChildScrollView`**; present via
  `showModalBottomSheet(isScrollControlled: true, ...)` with
  `padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom)`;
  wrap the action row in **`SafeArea`**.
- **Accept:** with keyboard open, the form scrolls, no overflow stripe, Save
  reachable and clear of the nav bar. Audit other bottom sheets for the same.

### Verify RSVP UI renders (the S21 acceptance)
- Confirm activity-kind plan items render **Going / Maybe / Declined** chips +
  a count summary inline on the Plan-tab card, disabled on closed/cancelled.
- **Accept:** create an `activity` item → chips appear → realtime cross-device.

---

## P1 — Navigation

### #1 — Back affordance on mobile detail screens
- Trip/event detail has a back arrow on web but none on Android → dead-end.
- Ensure the detail `Scaffold`'s `AppBar` shows a back (explicit `leading`
  `IconButton(Icons.arrow_back) → context.pop()`, or `automaticallyImplyLeading`
  with the route pushed as a sub-route so `pop()` works). Verify Android system
  back also returns to the list.
- **Accept:** from trip/event detail on Android you can return to the list via
  an on-screen control and system back.

---

## P2 — Polish

### #2 — Context-aware primary "+" (shows add-expense on ALL trip tabs)
- The add-expense FAB currently appears on **every** trip tab (Expense, Plan,
  Balance, Members). Make it per-tab:
  - **Expense** → add expense
  - **Plan** → add plan item (the Add plan item sheet)
  - **Members** → invite member (open the invite/QR/link flow)
  - **Balance** → **no add** (read-only summary) — hide the FAB
- **Accept:** each tab shows only its own action; Balance shows none; add-expense
  appears only on Expense.

### #3 / #3a — Lime-on-light audit (recurring)
- Audit every `AppColors.goLime` used as **text/icon/foreground on a light
  surface** (confirmed: the "Title" field label) → switch to Ink (or coral/plum).
- Keep goLime only as a **dark-surface accent or a tint behind Ink**.
- **Annotate `AppColors.goLime`** at its definition: *accent on Ink/dark only —
  never foreground on light* (stop the regression at the call site).
- Run **`design:accessibility-review`** on key screens (WCAG contrast).
- **Accept:** no lime text/icons on light; token carries the constraint.

### #5 — Event-type badge inside the event
- Show the item's type (activity/lodging/etc.) as a small badge/label in the
  event detail.

---

## Not code fixes (track separately)
- **#10 web join — needs a clean retest**, not a fix: Chrome logged in as
  zoethos → paste invite → verify `trip_members`. (Earlier failure was a
  self-join while logged in as tiziano, not a confirmed bug.)
- **#11 trips list stale until full reload** — investigate: refresh on resume,
  or a `trip_members` realtime subscription for the list. Lower priority.
- **Date-range picker** (enhancement) — design pass, post-merge.

---

## Done = 
`melos run ci` green + a **clean device pass**: sign-in resend works, Add plan
item is keyboard-safe with correct labels, activity chips render + realtime
cross-device, back nav works on Android, no lime-on-light, "+" is tab-correct.
