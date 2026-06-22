# Vamo navigation map (information architecture)

Source diagram: [`assets/ux-review-2026-06/04-trip-map.png`](assets/ux-review-2026-06/04-trip-map.png)
and [`assets/ux-review-2026-06/05-trip-wrapped.png`](assets/ux-review-2026-06/05-trip-wrapped.png).
This file is the canonical text record (the PNG can't be edited inline). Verified coherent against the
implemented app on 2026-06-22.

## A — Global shell (5-tab bottom nav)
`Trips · Activity · [+ Quick add] · Expenses · Profile` — `+` (lime) is the single primary action.
- **Trips** → Trips list → **Trip workspace** (the per-trip hub)
- **Activity** → cross-trip feed → drills into a trip
- **+** → Add expense / trip (modal)
- **Expenses** → cross-trip money home → drills into a trip's Expenses
- **Profile** → settings (Account · Prefs · Privacy)

## B — Inside a trip (hub-and-spoke off the Trip Dashboard)
Trip sections, all reached from the dashboard: **Plan · Expenses · Balances · Map · Members ·
Memories · Close report** (each with its action sheet: Add to plan / Add expense / Settle up / Invite /
Snapshot).

**Trip Map is a first-class trip *section*** (a peer of Plan/Expenses/Balances/Members/Memories), reached
from the dashboard — **not** a global bottom-nav tab. It is trip-scoped.

## Trip Map — its place, what feeds it, what it powers
```
Plan · POIs ─────┐
Expenses · places ┼──► Trip Map (journey replay) ──► Trip Wrapped (recap story)
Memories · photos ┘
```
- **Feeds it:** placed Visit POIs (coords), the place on each expense, geotagged memory photos.
- **Powers:** the assembled route + moments become **Trip Wrapped** at trip close — the map is Wrapped's
  data spine.

## Wave retag (decision 2026-06-22)
The diagram tags **Map** (and Wrapped) as "Wave 3" — **stale.** Per product decision, **Trip Map is core
flow, built now**: it shows always and fills live during a trip (the partial/progressive view is the
appeal), and it's part of the end-to-end flow testers must exercise. What is actually deferred is the
**heavy external-integration layer** (live transit / travel-means status, F), not the map.
- **Map P0 = now** — always-on progressive map from existing data (see
  `docs/slices/TRIP_MAP_P0_PROMPT.md`).
- **Map P1** — live per-member trails (needs "Follow me" I-P1 location sharing) + Replay.
- **Trip Wrapped** — consolidates the map's route + moments at close (the "non plus ultra" surface).
