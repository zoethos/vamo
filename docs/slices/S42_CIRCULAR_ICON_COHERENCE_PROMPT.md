# S42 — Circular icon coherence (shared white ring)

**Branch:** `feature/circular-icon-coherence` from `main` · **Est:** ~0.5 dev-day
**Design rule (new, record in the design system):** *every circular icon
badge/button carries a small **white** separating border (≈2px) — plus a subtle
shadow where it sits on a photo/colored surface — so all circular icons read as one
coherent family.* Add this rule to `docs/brand/S29_DESIGN_DIRECTION.md` (or
`DESIGN_BRIEF.md`).

## 1. Promote the ring to a shared element
The treatment already exists but is private: `member_avatar_row.dart:19`
(`_avatarRing = BorderSide(color: Colors.white, width: 2)`). Move it into **app_core
design** as a reusable element — e.g. `VamoCircleIcon` widget (or a
`circularIconDecoration({Color fill})` helper + a `kVamoCircleBorder` constant) — so
every circular icon uses one source, not per-widget copies.
- Treatment: `fill` (per use) + **2px white border** + a subtle soft shadow for
  separation on photos/colored backgrounds.

## 2. Apply to every circular icon (audit)
- **Camera / capture button** (`trip_dashboard_tab.dart:320`): currently
  `IconButton.filled` with `Colors.white.withValues(alpha: 0.92)` (reads **gray** over
  the image) and no ring. → **solid white fill** + the shared white ring + shadow.
  Founder-specified: white, not gray.
- **Participant avatars + "+" add tile** (`member_avatar_row.dart`): already ringed —
  switch them to the shared element so there's a single definition.
- **Activity row avatar** (`activity_screen.dart:136`), **snapshot circles**
  (`snapshot_card.dart:211,267`), the **My Trips notification bell**, and any other
  `CircleAvatar` / `IconButton.filled` / `BoxShape.circle` icon → apply the shared ring.
- App-bar back/⋯ (if rendered as plain icons, not circular badges) are out of scope
  unless they're shown as circular buttons over the hero — if so, ring them too.

## 2b. Avatar strip spacing (breathing room both sides)
The participant avatar strip still **touches the Total Spent card** below it and
**overlaps the event dates** above it. Give the avatar band clearance on both sides
(`trip_dashboard_tab.dart`):
- **Gap below (above the card):** the avatar row is `PositionedDirectional(bottom:
  cardHeroOverlap, …)` — sitting right at the card's overlapping top edge. Add a gap:
  `bottom: cardHeroOverlap + space.x3` so the avatars sit clearly above the card, not
  touching it.
- **Gap above (below the dates):** shrink the circles (member avatars `radius 22→18`,
  "+" tile `48→40`, keep the ring), set `avatarBandHeight = 40.0 + space.x4`, and bump
  the title/dates clearance `bottom: avatarBandHeight + space.x2 → + space.x3` so the
  dates sit clear above the strip.
- `heroBackgroundHeight` derives from these (`:67–68`) — verify the hero still ends at
  the correct card-overlap point and nothing clips. (This supersedes/duplicates S41
  §1d — included here so it lands in one pass even if S41 isn't on this branch.)

## 3. Verification
- `melos run ci`; update goldens that contain circular icons (dashboard hero,
  avatar row, activity, snapshot) light + dark.
- A11y: the white ring + shadow keep icons legible on both light bg and the photo
  hero; contrast of the icon glyph vs its fill stays ≥3:1.
- **On-device** (S25 Ultra): camera button is solid white (not gray) with a white
  ring; all circular icons share the same ring; consistent on light + dark.

## 4. Reviewer checklist
- [ ] One shared circular-icon element in app_core (no per-widget ring copies)
- [ ] Camera button: solid white fill + white ring + shadow (not gray)
- [ ] Avatars, add tile, activity, snapshot, notification bell all use the shared ring
- [ ] Design rule recorded in the design doc
- [ ] Goldens + a11y + device pass; light + dark

## Notes
- Pure styling; no behavior/data changes.
- Pairs with S39 (which introduced the avatar ring) and S41 (hero) — this generalizes
  the ring into a system rule.
