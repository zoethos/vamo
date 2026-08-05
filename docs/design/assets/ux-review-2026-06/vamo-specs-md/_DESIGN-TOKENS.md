# Vamo — Shared Design Tokens & Conventions

Every spec in this folder references these. Read this first; each view doc only lists its *view-specific* accents on top of this.

## Palette
```
ink            #0C0E16   primary text · selected fills · dark seg/pills · summary strip bg
inkSoft        #2A2E3A   body text
slate          #6b7280   secondary text · muted icons · meta labels
mute           #8a93a0   captions · meta lines
mute2          #9aa0ac   faint captions · placeholder text
lime           #C6FF00   THE primary action — fill only, ONE per screen (CTA / FAB)
plum           #6A2D6F   brand accent · Lodging type · "AI / Advanced"
coral          #FF5B4D   Visit type · dates/calendar · range tint · "you owe" amounts
coralText      #D7402F   small destructive/owe text on light (use instead of coral when <14px)
jade           #00A892   times · Bike · "settled / open now" · positive
jadeBright     #00C2A8   Train type
sky            #21B7D7   Flight type
carOrange      #FF8A3D   Car / Transfer accent (also #FFA766 lighter transfer tint base)
teal           #07595C   POI / place-info accent (info action, place-info card)
surface        #FFFFFF
appBg          #FAFAFB   in-phone screen background
canvas         #e7e5df   mockup page backdrop (NOT app chrome — design-doc only)
hairline       #ECEDF1   card borders (also #F0F1F4 lighter row dividers)
border         #E2E4EA   input/field borders
borderDash     #d7dae0   dashed add borders · secondary button borders
chipBg         #F1F2F5   unselected chips
segBg          #EEF0F4   segmented-control / pill track · unselected day pills
```

## Type system — the six plan-item types (one source of truth everywhere)
| id | name | icon (MSO) | accent | tint (accent+alpha) |
|---|---|---|---|---|
| `visit` | Visit | `place` | coral `#FF5B4D` | `#FF5B4D14` |
| `train` | Train | `train` | jadeBright `#00C2A8` | `#00C2A814` |
| `flight` | Flight | `flight` | sky `#21B7D7` | `#21B7D714` |
| `transfer` | Transfer | `sync_alt` | orange `#FFA766`/`#FF8A3D` | `#FFA76622` |
| `lodging` | Lodging | `bed` | plum `#6A2D6F` | `#6A2D6F14` |
| `other` | Other | `event`/`more_horiz` | slate `#6b7280` | `#6b728018` |

The picker accent, the search/focus border, the timeline spine dot, the activity/expense badge, and the Plan icon for a type are **all the same accent**. Tint = accent + `14`–`22` hex alpha.

## Fonts
- Text: system stack `-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, sans-serif`.
- Icons: **Material Symbols Outlined** throughout. (Flutter: `Icons.<name>` — names map 1:1.)
- Weights used: 600 (medium), 700 (bold), 800 (display/numbers). Headings/big numbers are 800.

## Phone shell (mockup container — not part of the app build)
The design docs frame each screen in a 320–330px-wide device: `appBg` background, 42px radius, 11px `ink` bezel. **This is presentation chrome.** Build the screens as normal full-bleed Flutter scaffolds; ignore the bezel.

## Iron rules (enforced by review)
1. **Lime = one primary action per screen.** FAB, Save, Settle up, Confirm. Never decorative, never on text <14px, never on a passive/log screen (it has no primary action).
2. **One accent per context.** A screen scoped to a type uses that type's accent for *all* of its emphasis (icon, focus border, highlight). No mixing plum+teal+coral in one field.
3. **M3 rows, day-grouped, single-line.** Lists across Activity / Expenses / Plan share row language: leading 34–38px thumbnail/icon-tile with a small accent badge, two text lines both `maxLines:1 + ellipsis`, quiet trailing (amount or chevron), grouped under a small uppercase day label.
4. **5-slot bottom nav with docked context FAB.** Trips · Activity · [＋] · Expenses · Profile. The center lime ＋ is context-aware: "+expense" on Expenses, "+trip" elsewhere. 56px bar, FAB 50×50px radius 16, lifted -22px, `0 6px 16px rgba(198,255,0,.5)` shadow.
5. **AI is an accelerator, never a gate.** Any AI flow has an equal-weight manual escape hatch beside it.
6. **Standard CTA button:** full-width, `lime` fill, `ink` text, no border, radius 14px, 15px/800, vertical padding 15px, shadow `0 6px 16px rgba(198,255,0,.4)`.
7. **Standard field:** 1.5px `border`, radius 13px, padding ~12–13px, `surface` bg, gap 10px, leading 20px icon. Focused/active field: border = context accent + `box-shadow:0 0 0 3px {accent}1A`.
