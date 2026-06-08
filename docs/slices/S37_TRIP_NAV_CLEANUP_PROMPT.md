# S37 — Trip nav cleanup: drop the redundant tab bar (dashboard = hub)

**Branch:** `feature/trip-nav-cleanup` from `feature/mytrips-dashboard-fidelity`
(or main once S35 merges) · **Est:** ~1–1.5 dev-days
**Why:** the trip detail still shows the old top **TabBar** (Overview · Expenses ·
Plan · Balances · Members) AND the new dashboard's **4 quick-action tiles** — two
controls doing the same navigation. The TabBar is a leftover from the pre-dashboard
UI. Remove it; the Overview dashboard becomes the hub and the quick-actions are the
real navigation into sections.
**Out of scope:** changing section *contents*; new features.

## 0. Current wiring (what to change)
- `trip_home_screen.dart`: `TabController` (`:63–74`, `:114–144`), **`TabBar`**
  (`:220`), **`TabBarView`** (`:236`), per-tab **FAB** logic keyed on
  `_tabController.index` (`:287+`).
- Dashboard quick-actions call `_tabController.animateTo(...)` (`:247–255`) — they
  switch tabs, they don't navigate.
- **No routes** for sub-sections — only `AppRoutes.trip(id)` = `/trips/:id`.
- Deep-links rely on tab index today: `initialTab == 'balances'` jumps the
  controller (`:128–129`); push-notification routes + the S22 close-report route
  must keep working.

## 1. Target model — hub + section routes (recommended)
- **Trip detail = the Overview dashboard only.** Remove `TabBar`, `TabBarView`, and
  the `TabController` from `trip_home_screen.dart`; render `TripDashboardTab`
  directly under the app bar.
- **Add section routes** (nested under the trip):
  `/trips/:id/expenses`, `/trips/:id/plan`, `/trips/:id/balances`,
  `/trips/:id/members`.
- **Wrap each existing tab body as a standalone screen** (its own `Scaffold` + app
  bar with title and back-to-dashboard + its own FAB):
  - Expenses screen → FAB "Add expense"
  - Plan screen → FAB "Add plan item" (`openAddPlanItem`)
  - Balances screen → no FAB (read)
  - Members screen → FAB "Invite" (`openInviteFlow`); keeps the dedup fix (no inline button)
  Capture stays an **action on the dashboard hero** (S30/S33) — not a section.
- **Quick-action tiles `context.push` the new routes** instead of `animateTo`.
- **Delete the per-tab FAB block** in `trip_home_screen.dart` — each section screen
  owns its FAB now; the dashboard itself has no FAB (actions via hero + quick-actions).

## 2. Deep-links / routing (preserve behavior)
- `initialTab == 'balances'` → route directly to `/trips/:id/balances` instead of
  setting a tab index.
- Push-notification routes + the **S22 close-report** deep-link must still land on
  the right screen (close report opens as it does today; settle/lifecycle nudges
  route into the correct section route).
- Back from any section returns to the **dashboard** (`/trips/:id`), not the trips
  list. The dashboard's app-bar back returns to the trips list as today.

## 3. Verification
- `melos run ci` green.
- **No TabBar** anywhere in the trip detail; goldens updated (the trip detail golden
  loses the tab strip).
- Quick-action tiles navigate to the four section routes; back returns to the
  dashboard; the hub shows hero + avatars + total/donut + quick-actions + activity.
- Each section screen has the correct FAB (add expense / add plan / invite; balances none).
- Deep-links: `initialTab=balances`, a push-notification route, and the S22
  close-report link all land correctly.
- Negative assertion: tapping a quick-action does **not** rely on a `TabController`
  (it's gone); no dead `animateTo`/index code remains.
- **On-device pass** (S25 Ultra): open a trip → dashboard only (no tab strip) →
  tap each quick-action → correct section opens → back → dashboard. Light + dark.

## 4. Reviewer checklist
- [ ] TabBar/TabBarView/TabController removed from `trip_home_screen.dart`
- [ ] Trip detail renders the Overview dashboard directly
- [ ] Four section routes added; each a standalone screen with app bar + back to dashboard
- [ ] Quick-actions `push` routes (no `animateTo`); no dead tab-index code
- [ ] FAB moved per-section (expense/plan/invite; balances none); dashboard FAB-less
- [ ] Capture remains a hero action, not a section
- [ ] Deep-links preserved (balances initial, push routes, S22 close-report)
- [ ] Goldens updated (no tab strip); a11y; device pass green

## Notes
- Simpler interim (NOT recommended): just hide the `TabBar` widget but keep the
  `TabBarView`/controller + `animateTo`. It removes the visible redundancy in one
  line, but leaves **no way back to Overview** from a section (no tab strip, app-bar
  back exits the trip) — so do the route model instead; it's the correct hub-and-spoke
  navigation the reference implies.
- This is the natural close-out of the S33/S35 redesign: dashboard hub, sections as
  destinations.
