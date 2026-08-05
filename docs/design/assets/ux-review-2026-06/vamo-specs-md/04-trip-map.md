# Implementation Prompt — Trip Map (journey replay) · screen 04

**For:** Codex / Claude Code · **Stack:** Flutter + M3 · **Source:** `Vamo UX Improvements.dc.html` §04 (concept frame). Tokens & rules: `_DESIGN-TOKENS.md`. **Status: roadmap Wave 3 — not yet built.** Build to this concept when scheduled; it lives as a **section inside a trip** (see `../nav-map/NAVIGATION_MAP_SPEC.md`), not a top-level tab.

**Why it matters most (review H4):** the README calls the journey replay "the moat — no incumbent does this," yet it exists only as a "coming soon" fake door. This is the clearest representation of the whole concept.

---

## Layout — a dark, immersive map screen

Full-bleed **dark** scaffold (`ink` shell). Status bar + app-bar text are white. App bar: `arrow_back` 22px + trip title "Amalfi Coast" 16px/700 (flex) + `ios_share` 21px.

**Map canvas** (fills the screen): a dark radial-gradient base `radial-gradient(120% 80% at 80% 10%, #2a1840, #1a1030 45%, #0c0f1c 100%)` with a couple of soft colored glow blobs for depth.
- **Trails:** one SVG path per member, each in that member's brand color, 3.5px round stroke. A faint dashed white "full route" path sits underneath. **Toggled trails fade to ~0.12 opacity** instead of disappearing. Luca's trail is dashed (`stroke-dasharray:2 7`). Trails are clipped to the current day (drawn up to the scrubber position).
- **Pins:** 34px white-bordered color circles with a member initial, dropped at located stops; only pins with `day <= currentDay` are shown.
- **Moment thumbnail:** a 58px rounded gradient tile with a `photo_camera` glyph, pinned on the route — photos / placed expenses become moments.

**Bottom control panel** (`#14111f`, padding 14px 16px 16px):
- **Member toggle chips** (gap 7px): "You" (coral dot), "Mara" (jadeBright dot), "Luca" (orange dot). Active chip = colored 1px border + tinted bg + white text; inactive = faint white border, transparent. Tapping toggles that trail.
- Row: "Day {n} of 8" 12px/700 white (left) + a lime **Replay** pill (`play_arrow` 14px + "Replay") that animates the trail drawing in.
- A **day scrubber** — a range slider (min 1, max 8, `accent-color:#C6FF00`) driving the replay. Seed of the Wave-5 branching playback.

## Concept notes (carry verbatim)
- **Every member's trail on one timeline**, each a brand color, toggleable — the "choose whose path to follow" replay. Moments (photos, expenses with a place) pin to the route.
- **A day scrubber** drives the replay; lime "Replay" animates the trail drawing in.
- **Data hooks already exist:** receipts capture lat/lng/time (EXIF), places resolve per expense, capture feeds the snapshot. The map is where that data finally pays off.
- **What feeds it:** placed Plan visits (POIs), the place on each expense, geotagged Memories — no extra entry. **What it powers:** the assembled route + moments become Trip Wrapped at close.
