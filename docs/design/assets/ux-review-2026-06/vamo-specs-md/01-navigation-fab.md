# Implementation Prompt — Navigation & primary action (5-slot nav + FAB) · screen 01

**For:** Codex / Claude Code · **Stack:** Flutter + M3 · **Source:** `Vamo UX Improvements.dc.html` §01 (Proposed frame). Tokens & rules: `_DESIGN-TOKENS.md`. The "Current" 4-slot frame is the rejected build.

**The fix (review H1):** the shipped shell is a 4-slot bar (Trips · Activity · Expenses · Profile) with **no center FAB**, and the app-bar carries a "+". Restore the spec'd **5-slot nav with a docked lime goLime FAB**. Consequence today: logging an expense — the core loop, highest-frequency action — has no global entry (≈3–4 taps). It also explains why goLime, the signature action color, is absent from live flows.

---

## Bottom nav (the change)
- **5 slots:** `Trips · Activity · [＋] · Expenses · Profile`. 58px tall bar, 1px `#E9ECF2` top border, `appBg`/`surface` background, items `justify-content:space-around; align-items:flex-end`.
- Each tab item: column, gap 2px, padding-bottom 6px — a 23px MSO icon over a 10px label. Active = `ink`, label 600; inactive = `mute2`.
  - Trips `luggage` · Activity `timeline` · Expenses `receipt_long` · Profile `person`.
- **Center docked FAB:** a 56×56 lime square, radius 18, lifted `margin-top:-26px`, `add` 30px `ink`, shadow `0 8px 20px rgba(198,255,0,.55)`. Optionally a pulsing ring behind it (a 56×56 2px-lime circle, `@keyframes` scale 1→1.7 + fade, 2.2s infinite) and a small "1" notification badge (22px lime circle, ink text, 2px ink border) top-right.
- **Context-aware ＋:** opens "+expense" on the Expenses tab (and a trip's expense view), "+trip" elsewhere. Retire the app-bar "+". One consistent metaphor.
- Flutter: use **M3 `NavigationBar` + docked FAB** (`floatingActionButtonLocation: centerDocked`) — not a hand-rolled `BottomAppBar`.

## App bar change
The Trips screen header loses its trailing `add` (kept only `notifications`). Header: a 28×28 radius-8 brand-gradient logo chip (`linear-gradient(135deg,#07595C,#6A2D6F)` with a 9px lime dot) + "My Trips" 19px/700 + `notifications` 22px.

## Trips screen context (unchanged chrome around the nav)
Filter chips (All/Upcoming/Past — `ink`/white selected, `#E9ECF2`/`inkSoft` idle). A 172px featured trip hero card (radius 16) with the brand gradient `linear-gradient(135deg,#FF5B4D,#FFA766 55%,#6A2D6F)`, bottom scrim, title + "May 12 – May 20 · 4 friends", and a top-right **"You're owed €312"** pill (`rgba(12,14,22,.55)` bg). Then an "Upcoming · See all" list of 46px trip rows (gradient thumbnail + name + dates + chevron).

## Why (carry verbatim)
- The center **goLime FAB** restores the spec'd 5-slot nav; logging an expense drops from 3–4 taps to one, from anywhere.
- **Context-aware:** "+" adds an expense on Expenses, a trip elsewhere — one metaphor; the app-bar "+" is retired.
- Brings the **signature action color** into the core loop — the running app finally reads like the brand board, not a default Material build.
- Source of truth: DESIGN_BRIEF.md → Navigation, and both approved brand boards.
