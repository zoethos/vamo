# S27 — Mobile UI polish I (tester readiness)

**Branch:** `feature/ui-polish-1` · **Est:** ~2–3 dev-days · **Depends:** S21 merged
**Why:** repo-grounded design pass (2026-06-06) found the app works but feels
"slice-assembled" — too many competing actions, hardcoded copy, state-heavy
flows not visually calm. This is **tester-readiness polish + mobile-shell
simplification before more feature mass.**
**Recommended order:** **before S22 / before the internal-build tester onboarding**
— testers hit all of this. S22's close report should then follow the principle
established here: **personal, sparse, actionable, state-legible.**
**Inputs:** `docs/slices/DEVICE_TEST_FINDINGS.md` (UX enhancements + #3/#3a/#12), this pass.
**Out of scope:** full money-screen redesign (principle only here; full pass later),
new features.

## 1. Theme token fix — the root cause (do FIRST, highest leverage)
`ColorScheme.primary` is `goLime`, contradicting the design brief — so every
widget using the `primary` semantic role renders lime, which is the source of
the recurring **lime-on-light** regressions (#3/#3a).
- **`primary` / primary semantic roles → `deepPlum` / ink.** Reserve **`goLime`
  only for filled CTAs/FABs with ink foreground** (the "Create trip" / Save
  pattern, which is correct).
- **Annotate `AppColors.goLime`** at its definition: *accent on ink/dark only —
  never a foreground on light, never `ColorScheme.primary`.*
- Re-audit screens after the token change (a lot of lime-on-light should vanish
  automatically). Run `design:accessibility-review` for WCAG contrast.
- File: `packages/app_core/lib/src/design/app_theme.dart`.

## 2. Simplify trip top chrome
Trip screen today: back, title, lifecycle overflow, settings, share, tabs, **and**
a contextual FAB — crowded on mobile.
- Keep **back + title + one "More" (⋯) menu**. Move **settings / share /
  lifecycle actions** into that single More sheet/menu.
- Keep the contextual FAB (already tab-aware from the earlier batch).
- File: `packages/feature_split/lib/src/trips/trip_home_screen.dart`.

## 3. One coherent invite action (Members) — resolves #12
Members must not have separate big buttons + FAB + contact button.
- **One primary "Invite" action** → opens the method sheet:
  **Text message · Email · Share link · QR**. (S26 contact path becomes an entry
  in this sheet, not a separate surface.)
- Remove the duplicate "Invite Amigos" buttons.
- File: `packages/feature_split/lib/src/trips/members_tab.dart`.

## 4. RSVP chips — unmistakably stateful (+ device-validate)
RSVP must read clearly both ways: **selected**, **declined** (a real response,
not a dead label), **disabled while saving**, and **clear failure feedback**.
- Consider Material 3 single-select **`SegmentedButton`** (compact, idiomatic;
  see DEVICE_TEST_FINDINGS) with icon+label; selected fill must be ink/teal,
  **not lime-on-white**.
- This is part of the **next device pass** (state transitions only show on device).
- File: `packages/feature_split/lib/src/plan/plan_event_rsvp_chips.dart`.

## 5. Demote "coming soon" teasers
The map "coming soon" card sits above real trip content, making useful content
feel secondary.
- **Hide or demote** coming-soon cards for internal testers; the **Plan tab
  leads with plan content**. (Keep a teaser only if it unlocks a known feedback
  path.)

## 6. Money UX — scan-first hierarchy (principle + apply to S22)
Balances/governance are correct but text-heavy. Make the four questions
instantly visible: **"Who owes whom?" · "What's disputed?" · "What action is
mine?" · "What's final?"**
- S27: apply scan-first hierarchy to the **Balances** surface (lead with the
  answer, not a list).
- **S22 close report** must be designed as a **statement**, not another list —
  this principle is binding on S22.
- (A full money-screen redesign is a later pass; S27 does the hierarchy on the
  primary balance view.)

## 7. Hardcoded-copy sweep (tester flows)
Auth / create-trip / add-expense / balances still have hardcoded user-facing
strings. Not fatal for English testers, but weakens consistency + RTL.
- **Sweep visible strings in the top tester flows into ARB** (parameterized, no
  concatenation, directional). Scope to tester-facing screens this pass.

## 8. Verification
- `melos run ci` green.
- **Golden tests** for the touched screens at **Android small-screen** size
  (catch overflow/crowding regressions like the add-sheet 137px one).
- **RTL smoke** on the swept flows (directional ARB, no clipped layouts).
- **Device pass (S25):** trip chrome reads calm; one Invite action; RSVP state
  transitions (select/decline/saving/failure) correct on device; no lime-on-light
  anywhere; coming-soon demoted; Balances scan-first.
- Negative-assertion widget tests where behavior changed (e.g., duplicate invite
  buttons gone; settings/share live only in the More menu).

## 9. Reviewer checklist
- [ ] `ColorScheme.primary` off `goLime` (→ deepPlum/ink); goLime only on filled CTA/FAB w/ ink fg; token annotated
- [ ] No lime-on-light remaining (post-token audit + a11y contrast pass)
- [ ] Trip app bar = back + title + one More menu (settings/share/lifecycle moved in)
- [ ] Members = one Invite action → method sheet (text/email/link/QR); duplicates removed (#12)
- [ ] RSVP chips state-legible (selected/declined/saving/failure); selected fill not lime-on-white; device-validated
- [ ] Coming-soon teasers hidden/demoted; Plan leads with content
- [ ] Balances scan-first; close-report principle handed to S22
- [ ] Tester-flow hardcoded copy → ARB (parameterized, directional)
- [ ] Golden (small-screen) + RTL smoke + device pass green

## Follow-ons (S28+ "Mobile UI polish II")
Tab icons/IA (Expense/Plan/Balance/Members/Capture; is Capture a tab or action?),
date-range picker (single range vs two fields), full money-screen redesign,
space-efficiency sweep across remaining screens.
