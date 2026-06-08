# S38 — UI polish pass (nav, avatars, dates, swipe, Plan +/checklist)

**Branch:** `feature/ui-polish-pass` from `main` (after S35/S37 merge) · **Est:** ~2.5–3 dev-days
**Why:** founder UI refinements after the redesign. Six focused items; consume S29
tokens; light + dark; keep the current logo. No backend/schema changes.

## 1. Bottom nav strip too tall
`main_shell.dart` — the `BottomAppBar` (`:58`) + each nav item
(`Padding(symmetric(horizontal:8, vertical:4))` + `Column[Icon(24), SizedBox(2),
labelSmall]`, `:147–156`) leave too much space above/below the icons.
- Set an explicit, **smaller `BottomAppBar` height** (the M3 default is tall) and
  trim item vertical padding so it's a tight strip — icons + tiny labels, minimal
  dead space. Keep the centre FAB notch alignment.
- A11y: keep touch targets ≥48dp even as the visual strip shrinks (padding can be
  smaller than the tap target).

## 2. Avatar placeholder: person shape, not "V"
`member_avatar_row.dart:33` and `members_tab.dart:110` render
`displayName[0].toUpperCase()` → shows "V" for Vamo/blank names.
- Build **one shared `VamoAvatar`** widget: when there's no photo, show a **person
  silhouette** (`Icons.person`/`person_outline`) on a tinted circle — not a letter.
- Optional: a very small name label under/beside the badge where space allows (not
  inside the circle).
- Brand/placeholder badge (mockup/empty slots) uses the **Vamo mark / "vamo"
  wordmark**, not a letter.
- Replace every `CircleAvatar(child: Text(initial))` with `VamoAvatar` (avatar row,
  members roster, anywhere else avatars render).

## 3. Dates: optional + start ≤ end + clearer picker actions
- **Optional:** dates are not mandatory anywhere (create trip + plan item). Already
  partly true (`_startDate`/`_endDate` nullable, `onClear`) — make "no date" a
  first-class, obvious path.
- **Validation:** enforce **start ≤ end** wherever both are set — in
  `create_trip_screen` (the `:190` check exists but isn't catching it — fix/verify)
  **and** `plan_item_sheet` (add it). Only validate when both dates present (since
  optional). Show a clear inline error, don't silently allow end-before-start.
- **Picker actions — relabel to `Cancel · Skip · Select`** (OK is too generic):
  - `Select` = confirm the chosen date (Material `confirmText`).
  - `Cancel` = abort, no change (Material `cancelText`).
  - `Skip` = proceed with **no date** (clears/leaves empty). Material
    `showDatePicker` only has two buttons, so add Skip via a small custom date
    dialog wrapper **or** a field-level "Skip / No date" affordance next to the
    picker. Pick one; keep it consistent across create-trip and plan-item.

## 4. Swipe actions instead of 3-dot menus
Replace `PopupMenuButton` edit/delete with **swipe left/right** actions on list rows:
- `plan_tab.dart:275` (plan items), `plan_event_tile.dart:122` (events), and the
  members role menu (`members_tab` `_roleTrailing`) — and expense rows if they have
  a 3-dot menu.
- **Dependency decision (call out in PR):** `flutter_slidable` gives clean
  two-direction action panes (e.g. swipe-left → Delete, swipe-right → Edit) — register
  in `docs/DEPENDENCIES.md` if used. Zero-dep alternative: `Dismissible` with
  `confirmDismiss` for delete + a tap-to-edit, but it's clumsier for two actions.
  Recommend `flutter_slidable` for the two-action UX the founder described.
- Destructive (delete) needs confirm; keep undo where it exists. A11y: swipe actions
  must have an accessible equivalent (long-press menu fallback for screen readers).

## 5. Plan: small "+" instead of the big lime button + tidy the checklist
- `plan_tab.dart:83/103` — the big lime `FilledButton` "Add plan item" eats vertical
  space and (per founder) collides with the checklist. **Replace with a small "+"
  icon** in the Plan section header/app bar (mirroring the main screen's "+" next to
  the notification bell).
- Tapping "+" opens a **small add menu/sheet** to choose: **Add event/plan item**
  or **Add checklist item**. (This refines S37's Plan-screen FAB → a header "+" the
  founder prefers.)
- **Checklist coherence:** the inline checklist `TextField` (`plan_tab.dart:168–182`)
  breaks the UI style. Move checklist creation/add behind the "+" menu, and restyle
  the checklist section + inputs to S29 tokens (`CheckboxListTile` + token fields),
  so it reads as part of the system, not a bolted-on form. Keep the existing
  checklist data/behavior (collaborative, `checkedBy`/`checkedAt`).
- **Checklist items can't be deleted today (bug):** the delete is fully built —
  `planRepository.deleteListItem(id)` (`plan_repository.dart:412`) + the
  `trip_list_items_delete` RLS policy (`0016:95`, with a block-delete-on-closed
  guard) exist — but `_ChecklistSection` only wires `onToggle`, never `onDelete`.
  Wire `onDelete: (id) => repo.deleteListItem(id)` and add **swipe-left to delete**
  on each checklist row (same `flutter_slidable` pattern as §4). Respect `readOnly`
  (no delete on closed trips; RLS already blocks it). Confirm on delete.

## 6. Verification
- `melos run ci` green.
- **Goldens** (light+dark+small+RTL) for: bottom nav (shorter), avatar row (person
  silhouette), plan screen (header "+", tidied checklist), a swiped row state.
- A11y: nav touch targets ≥48dp; swipe actions have a non-swipe fallback; avatar
  silhouette contrast; date error legible.
- **On-device pass** (S25 Ultra): nav strip tighter; missing avatars show a person
  shape not "V"; date can be skipped and start>end is blocked; swipe edit/delete
  works on plan/events/members; Plan "+" opens the add menu; checklist looks
  coherent. Light + dark.

## 7. Reviewer checklist
- [ ] Bottom nav strip shorter; targets still ≥48dp; FAB notch intact
- [ ] Shared `VamoAvatar`; person silhouette (no "V"); brand placeholder = vamo mark
- [ ] Dates optional everywhere; start≤end enforced (create-trip + plan) when both set
- [ ] Date picker actions = Cancel · Skip · Select (consistent)
- [ ] Swipe left/right edit/delete replaces 3-dot menus; confirm on delete; a11y fallback
- [ ] flutter_slidable registered in DEPENDENCIES.md (if used)
- [ ] Plan: small header "+" → add menu (event / checklist); big lime button removed
- [ ] Checklist restyled to tokens, no longer breaks coherence
- [ ] Consumes S29 tokens; light+dark; current logo; goldens + a11y + device pass

## Notes
- Pure UI/UX; no schema/RPC/data changes.
- Item 5 supersedes the Plan-screen FAB from S37 (header "+" instead).
