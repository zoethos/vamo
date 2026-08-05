# Vamo — View implementation specs (handoff to Codex / Claude Code)

Pixel-exact build prompts, one per designed view, derived directly from the interactive mockups. **Start with `_DESIGN-TOKENS.md`** (shared palette, the six-type system, and the iron rules) — every spec builds on it. Each spec says to match the standalone HTML mockup pixel-for-pixel and is framed for the Flutter/M3 stack.

## PNG → spec map

| PNG | Spec | Source mockup | Status |
|---|---|---|---|
| `01-navigation-fab.png` | `01-navigation-fab.md` | UX Improvements §01 | proposed |
| `02-add-expense.png` | `02-add-expense.md` | UX Improvements §02 | proposed |
| `03-balances.png` | `03-balances.md` | UX Improvements §03 | proposed |
| `04-trip-map.png` | `04-trip-map.md` | UX Improvements §04 | **Wave 3 — not built** |
| `05-trip-wrapped.png` | `05-trip-wrapped.md` | UX Improvements §05 | **Wave 3 — not built** |
| `06-profile.png` | `06-profile.md` | UX Improvements §06 | proposed |
| `07-add-to-plan.png` | → use `09` + `11` | UX Improvements §07 (early) | superseded |
| `09-add-to-plan-refined.png` | `09-add-to-plan-refined.md` | Add-to-Plan Refined (Visit) | proposed |
| `10-plan-view.png` | `10-plan-view.md` | Plan View | proposed |
| `11-add-to-plan-types.png` | `11-add-to-plan-types.md` | Add-to-Plan Types | proposed |
| `12-flight-resolved.png` | `11-add-to-plan-types.md` (Flight resolved state) | Add-to-Plan Types | proposed |
| `13-place-info-card.png` | `13-place-info-card.md` | Place Info Card + PlaceInfoCard | proposed |
| `14-activity-refactor.png` | `14-activity-refactor.md` | Activity Refactor | proposed |
| `15-expenses-refactor.png` | `15-expenses-refactor.md` | Expenses Refactor | proposed |
| `16-new-trip.png` | `16-new-trip.md` | New Trip (AI-assisted) | proposed |
| `17-date-scroller.png` | `17-date-scroller.md` | Date Scroller | **not built** |
| `18-advanced-travel.png` | `18-advanced-travel.md` | New Trip Advanced Travel | proposed |
| `19-mockup-index.png` | this folder (the full review deck) | UX Improvements (all §) | — |

All 18 view specs live in this folder. App-wide IA: `../../nav-map/NAVIGATION_MAP_SPEC.md`. Review rationale & priorities: `../../UX_REVIEW_BACKLOG.md`. `_DESIGN-TOKENS.md` is mirrored at the `docs/design/` root for convenience. (`../../TRAVEL_LEG_VIEW_SPEC.md` is the original combined date-scroller + advanced-travel write-up, now split into `17`/`18` here.)

## How to use
1. Read `_DESIGN-TOKENS.md`.
2. Open the matching standalone HTML mockup (`Vamo <Name> (standalone).html`) next to the spec.
3. Build to the spec; diff against the mockup and the PNG. Honor the acceptance bullets at the foot of each spec.
