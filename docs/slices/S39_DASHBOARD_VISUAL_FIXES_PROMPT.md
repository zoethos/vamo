# S39 — Trip dashboard visual fixes

**Branch:** `feature/dashboard-visual-fixes` from `main` (after S38 merge) · **Est:** ~1 dev-day
**Scope:** four visual refinements on the trip dashboard (`trip_dashboard_tab.dart`)
+ two light-theme tokens. Consume S29 tokens; light + dark; no backend.

## 1. Hero image wraps the avatar strip + overlaps the Total Spent card
Today the hero is a fixed `SizedBox(height: 200)` Stack (`:64`), with `MemberAvatarRow`
(`:135`) and `_TotalSpentCard` (`:167`) stacked **below** it.
- Make the hero image/gradient the **background** behind the avatar strip, extending
  **down to ~33% into the Total Spent card**.
- Layout: the **avatar row sits on the image**, and the **top ~1/3 of the Total Spent
  card overlaps the image** (card floats over the hero's bottom edge) — the reference
  composition. Implement via a `Stack` (hero as background) with the content column
  (avatars + total card) pulled up to overlap (negative offset / `Transform.translate`
  / `Positioned`), keeping the whole thing scrollable as one unit.
- Increase hero height accordingly so it reaches that overlap point; keep the title/
  dates scrim legible.

## 2. White border on participant avatars
`member_avatar_row.dart` circles use `surfaceMuted` with no border (`:42`).
- Add a **small white border ring** (`Border.all(color: Colors.white, width: ~2)`)
  around each participant circle so they emerge from the (now darker/photo) hero
  background. Apply to the "+" add tile too for consistency.

## 3. Light background is too yellow → whiter
`AppColors.cream = #FFF7EA` reads yellowish.
- Shift the light **`background`** to a **whiter near-white** — clearly whiter than
  cream but **not** pure white (the card `surface` stays `#FFFFFF`). Target something
  like `#FBFAF7`/`#FAF9F6` (a hair of warmth, no yellow cast). Adjust the `cream`
  token (or the light semantic `background`) only; dark theme unchanged.
- Deliberate softening of the warm-cream direction — founder finds it too yellow on
  device; keep warmth subtle, not absent.

## 4. Quick-action tiles → really white (not grey)
`_QuickActionTile` uses `colors.surfaceMuted` (mistGray grey, `:393`).
- Change the tile background to **`colors.surface` (#FFFFFF)** — really white.
- Because white tiles now sit on a near-white background (#3), add **separation**: a
  hairline border (reuse the Total Spent card's `divider 0.6` border) or a soft
  shadow, so the tiles read as cards, not blend in. Keep the teal icons.

## 5. Verification
- `melos run ci`; update dashboard goldens (light + dark + small + RTL).
- A11y: avatar white-border contrast; tile separation visible; title scrim over the
  taller hero still ≥4.5:1.
- **On-device** (S25 Ultra): hero image wraps the avatars and overlaps the top ~1/3
  of the Total Spent card; avatars have white rings; background reads white-not-yellow;
  the four action tiles are white with clear edges. Light + dark.

## 6. Reviewer checklist
- [ ] Hero behind avatar strip + overlapping top ~1/3 of Total Spent card; scrolls as one
- [ ] White ring on participant + add avatars
- [ ] Light `background` whiter (not yellow), card `surface` still pure white
- [ ] Quick-action tiles white with hairline border/shadow separation; teal icons kept
- [ ] Goldens + a11y + device pass; dark theme unaffected by the background change
