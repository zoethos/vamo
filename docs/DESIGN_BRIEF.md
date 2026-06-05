# Vamo design brief — identity pass (locked 2026-06-05)

Decisions: name **VAMO** (locked) · mark **V-arrow** (gradient coral→plum,
assets in `docs/brand/`) · navigation per the approved brand board's sample
screen. This brief is the contract for the identity implementation (W2-5).

## Design tokens (app_core/lib/src/design)

| Token | Hex | Usage |
|---|---|---|
| `sunsetCoral` | #FF5B4D | brand primary, owed amounts (large/bold only), gradient start |
| `apricot` | #FFA766 | warm secondary, gradient stops |
| `deepPlum` | #6A2D6F | gradient end, dark accents |
| `indigo` | #0F1126 | dark surfaces, dark pattern base |
| `jadeTeal` | #00C2A8 | positive/settled states |
| `blush` | #FFE6EC | soft fills, light pattern tint |
| `goLime` | #C6FF00 | THE action accent: FAB, primary CTAs, "all settled" chips |
| `ink` | #0C0E16 | text primary, icons on lime |
| `graphite` | #2A2E3A | text secondary |
| `mistGray` | #E9ECF2 | dividers, input fills |
| `warmWhite` | #FAFAFB | light background |
| `coralText` | #D7402F | DERIVED: coral for small text (board coral fails 4.5:1 on white) |
| `brandGradient` | coral→plum (topStart→bottomEnd, directional) | logo fields, covers fallback |

### Hard rules (enforced in review)
1. **goLime never carries white text/icons** — Ink only (3.0:1 vs white = fail).
2. **sunsetCoral on white**: ≥18px bold only; smaller → `coralText`.
3. **Wordmark/watermark**: white mark on gradient/photo, ink on light — never
   recolored per theme; position fixed (snapshot doctrine unchanged).
4. All new layouts directional (I18N_PLAN rules) — board's mock is LTR;
   mirror-ready from first commit.

## Navigation (board sample screen = target)

Bottom nav, 5 slots: **Trips · Activity · [+ FAB, goLime, Ink +] · Expenses · Profile**
- **Trips**: current trips list restyled — photo/gradient cards (cover =
  destination theme-pack gradient until trip photos exist; first trip photo
  when available), stat chips (photos/notes/receipts counts), owed/settled
  chip (coral owed / teal+blush settled / lime "all settled"), pill filters
  All/Upcoming/Past/Drafts.
- **Activity**: v1 = chronological feed from existing local data (expenses
  added, members joined, settlements) across my trips. Wave 2 events enrich it.
- **+ FAB**: context-aware — new expense inside a trip, new trip elsewhere.
- **Expenses**: cross-trip expense list (existing data, new query) with
  receipt thumbnails; filter by trip.
- **Profile**: profile + settings + About (version via package_info_plus,
  brand block with mark + "Si va?", licenses page, privacy policy link) +
  Vamo Plus placeholder + suggest-a-feature + dev locale toggle (debug).
- Gear-only settings entry: removed.

## App identity surfaces
- Launcher icon: `flutter_launcher_icons` from `docs/brand/app_icon.png`
  (regenerate 1024 master when vectorized).
- Auth screen: primary_mark above wordmark, gradient or light-pattern bg.
- Empty states: mark_ink subtle + brand copy ("Si va?").
- App bar (trips root): small mark left of title, like the board.
- Patterns: pattern_light/dark as optional scaffold backgrounds (subtle).

## Assets
`docs/brand/`: primary_mark, mark_white, mark_ink, app_icon, journey_mark,
pattern_light (+ pattern_dark pending). Production: vectorize primary mark
(reference also the vector road-and-sun board SVG for path technique).
Tagline: **"Si va?"** · secondary line: "Let's go. Together."

## Out of scope here
Theme-pack library UI (Wave 2 with entitlements), dark mode as a full theme
(tokens are ready; ship light-first), Events/TripBoard surfaces.
