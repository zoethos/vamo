# Implementation Prompt — App navigation map (information architecture)

**For:** Codex / Claude Code · **Source of truth:** `Vamo Navigation Map.dc.html` / `nav-map/Vamo-Navigation-Map.png`. Tokens: `_DESIGN-TOKENS.md`.

This is **not a screen to build** — it's the IA contract that the navigation structure must satisfy. Two charts: **A** = global navigation (the 5-tab shell); **B** = inside an opened trip (where the Trip Map lives). Status legend: **Built** (jade dot) · **Wave 2** (orange `W2`) · **Wave 3** (plum `W3`) · dashed box = modal sheet · solid line = navigation · dashed coral line = data flow.

---

## A · Global navigation
- **Launch → Auth & onboarding** (OTP · Apple · Google · QR) → **Main shell**.
- **Main shell = 5-slot bottom nav:** `Trips · Activity · [＋] · Expenses · Profile`. The center is the lime **context-aware ＋** ("+expense" on Expenses, "+trip" elsewhere) — it opens an **Add expense / trip** context sheet, it is **not** a tab destination.
- Tab homes: **Trips list** (all · upcoming · past) → opens a **Trip workspace** (chart B); **Activity** (cross-trip feed) — aggregates, drills into a trip; **Expenses** (cross-trip money home) — aggregates, drills into a trip's Expenses; **Profile** (Account · Prefs · Privacy).
- Key relationship: Activity and Expenses tabs are **aggregators that drill into the per-trip views**, not parallel destinations.

## B · Inside a trip (opened) — where the Map lives
- A **Trip Dashboard** hub (hero · recent) sits above the trip's section bar.
- **Trip sections are peers** on the trip's tab bar / dashboard: `Plan · Expenses · Balances · Map★ · Members · Memories · Close report (W2)`.
- **The Trip Map is a section _inside a trip_** — a peer of Plan/Expenses/Balances, **not a top-level tab.** This is the single most important structural point of the whole map.
- Section → sheet relationships: Plan→**Add to plan** (type → POI); Expenses→**Add expense** (amount → split); Balances→**Settle up**; Members→**Invite** (QR · link · contacts); Memories→**Snapshot** (share card).

## ★ Trip Map — its place & what feeds it
- **Where it sits:** a section inside an opened trip, beside Plan, Expenses, Balances, Members, Memories. Not a tab.
- **What feeds it (data flow):** placed **Plan** visits (POIs), the **place** on each expense, and geotagged **Memories** all drop pins on the Map — no extra entry needed.
- **What it powers:** the assembled route + moments become the **Trip Wrapped** recap at close — the share-the-story payoff. (Map = Wave 3, Wrapped = Wave 3.)

---

## Visual conventions of the diagram (if regenerating the chart)
Node = rounded-11 box on a white board (`#fff`, radius 16, soft shadow). Built nodes white with `#E4E6EC` border + jade dot; Wave 2 = orange-tinted border + `W2` badge; Wave 3 = plum + `W3`; modal sheets = dashed `#C2C6CF` border on `#FAFAFC`; shell/entry nodes = solid `ink` fill with white text; the lime ＋ node = lime fill. The **Trip Map node is emphasized**: 2px coral border + coral glow (`box-shadow:0 0 0 4px rgba(255,91,77,.16)`). Edges: solid gray `#c4c8d0` w2 = navigation (arrow `#b2b7c0`); dashed coral `#FF5B4D` = data flow / expansion (arrow coral). Region groupings = dashed `#d4d7de` rounded rectangles with an uppercase label.
