# S41 — Trip dashboard layout fixes (full-bleed hero + overlap gap)

**Branch:** `feature/dashboard-layout-fixes` from `main` (after S39 merge) · **Est:** ~0.5–1 dev-day
**Scope:** two layout issues on `trip_dashboard_tab.dart` + `trip_home_screen.dart`.
Consume S29 tokens; light + dark; no backend.

## 1. Bottom gap / wasted space (overlap implemented with Transform.translate)
The Total Spent card is pulled over the hero via
`Transform.translate(offset: Offset(0, -cardHeroOverlap))` (`trip_dashboard_tab.dart:~181`).
`Transform.translate` moves the card **visually only** — its full-height layout slot
stays, so the vacated `cardHeroOverlap` is never reclaimed and a phantom gap pushes
everything below down (the big space above the system nav).
- **Replace the translate with a real-layout overlap.** Options (pick one):
  - Put hero + avatar row + Total Spent card in **one `Stack`** sized to the actual
    visual height (hero visible height + card height − overlap), card `Positioned` to
    overlap the hero's bottom — subsequent content flows right after with no gap; **or**
  - keep the translate but **reclaim the space**: follow the translated card with a
    negative-equivalent `SizedBox(height: -cardHeroOverlap)` isn't valid, so instead
    wrap the hero+card in a `SizedBox`/`Stack` whose height already subtracts the
    overlap. Net: no dead space below the card.
- After the fix, sections (quick actions, recent activity) sit directly under the card.
- The remaining bottom space on a sparse trip (1 activity) is just a short page —
  recent activity already shows up to 5 (`take(5)`), so it fills as activity grows.
  Tighten inter-section spacing only if it still reads loose; the phantom gap is the
  real fix.

## 1b. The gap between the Total Spent card and the quick-action buttons
Same root cause as §1 — the `Transform.translate` on the card leaves a phantom slot
*directly* between the (visually-raised) card and the quick-action row. The §1
real-layout overlap fix removes this gap too; no separate change.

## 1c. Balances button missing (inconsistent member-count sources)
`showBalances = count > 1` uses `tripMemberCountProvider`
(`trips_providers.dart:28` → `watchActiveMemberCount`, counts only `status='active'`)
which returns **1** for a 2-participant trip, while the dashboard's avatars +
per-person use `tripMembersForExpenseProvider` (sees **2**). So Balances is hidden
and — because `showCapture = !showBalances` — the capture button wrongly shows.
- **Fix:** derive `showBalances` (and therefore `showCapture`) from the **same
  member source** the avatars/per-person use (`tripMembersForExpenseProvider.length
  > 1`), so the dashboard is internally consistent. Handle the loading state so it
  doesn't momentarily default to 1 and hide Balances.
- Align the **featured/compact trip-card participant counts** (`compact_trip_card.dart:30`,
  `featured_trip_card.dart:30`, both `tripMemberCountProvider ?? 1`) to the same
  source so the My Trips cards don't undercount the same way.
- Separately (root cause, lower priority): investigate why the 2nd member's local
  `status` isn't `active` (join/invite status sync) — but the unified-source fix is
  the robust UI fix regardless.

## 1d. Title/dates overlap the participant avatar strip
The trip title + dates sit only `space.x2` above the avatar band
(`bottom: avatarBandHeight + space.x2`), and avatars are `radius: 22` (44px) + a
48px "+" tile — so the dates row collides with the circles.
- **Shrink the circles a bit:** `member_avatar_row.dart` member avatars
  `radius: 22 → 18` (36px), the "+" add tile `48 → 40` (icon size proportionally),
  keep the 2px white border.
- **Pull the title/dates up:** reduce `avatarBandHeight` to match the smaller
  avatars (e.g. `40.0 + space.x4`) **and** increase the title/dates clearance from
  `space.x2 → space.x3` so there's a visible gap above the strip.
- `heroBackgroundHeight` derives from `avatarBandHeight` (`:67–68`), so it adjusts
  automatically; verify the hero still ends at the right card-overlap point.

## 2. Hero image full-bleed to the top of the screen
Today `trip_home_screen.dart` uses an opaque `AppBar` (`:105`) above the image, so the
hero starts below a plain strip. Extend the image to the very top (status bar + app
bar area); the bottom (card overlap) stays as-is.
- `Scaffold(extendBodyBehindAppBar: true)`.
- `AppBar`: `backgroundColor: Colors.transparent`, `elevation: 0`,
  `scrolledUnderElevation: 0`; **white foreground** for the back + ⋯ icons so they're
  legible on the image (they already sit over the `GradientScrim`; ensure the scrim
  reaches the top — extend `GradientScrim` to cover the status-bar band, or add a
  subtle top scrim).
- The hero in `trip_dashboard_tab.dart` must fill **from y=0** (behind the status
  bar). Add top inset (`MediaQuery.padding.top`) inside the hero so the trip title/
  dates aren't hidden under the back/⋯ icons.
- Keep the capture/⋯ controls tappable; keep title contrast ≥4.5:1 over the image.

## 3. Verification
- `melos run ci`; update dashboard goldens (light + dark + small + RTL).
- A11y: back/⋯ icons legible on the image (scrim); title contrast over the now-taller
  hero ok.
- **On-device** (S25 Ultra): no dead gap above the system nav; sections flow under
  the Total Spent card; hero image reaches the very top (under status bar) with
  legible back/⋯; card overlap at the bottom unchanged. Light + dark.

## 4. Reviewer checklist
- [ ] Overlap no longer uses layout-leaking Transform.translate; no phantom gap below the card
- [ ] Content flows directly under the Total Spent card
- [ ] Scaffold extendBodyBehindAppBar + transparent AppBar; back/⋯ white + legible (scrim)
- [ ] Hero fills from y=0 (behind status bar); title not hidden under app-bar icons
- [ ] Card overlap (bottom) unchanged; goldens + a11y + device pass
