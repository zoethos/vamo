# Implementation Prompt — Plan view (day timeline) · screen 10

**For:** Codex / Claude Code · **Stack:** Flutter + M3 · **Source of truth:** `Vamo Plan View.dc.html`. Tokens & rules: `_DESIGN-TOKENS.md`. Match pixel-for-pixel.

The itinerary that Add-to-Plan feeds into: a **day-grouped time-rail timeline** using the same six types. Same icon/accent that named an item in the picker identifies it here. Lime is reserved for the add button only.

---

## Layout

App bar (padding 6px 18px 10px): `arrow_back` 24px + two-line title "Plan" 19px/800 over "Amalfi Coast · 4 friends" 12px `slate` + trailing `tune` 23px `inkSoft`.

**Day pills** (horizontal, gap 8px, padding 2px 18px 12px): each 46px wide, column, gap 2px, padding 8px 0, radius 13px. Selected: `ink` bg, white. Unselected: `segBg` bg, `inkSoft`. Top line = weekday 10px/700 (.04em, opacity .7), bottom = day number 16px/800. Demo days: MON 12 … FRI 16. Tapping switches the day.

**Day heading** (12px/700 `slate`, margin-bottom 10px): e.g. "Tue, May 13 — Positano".

**Timeline** (scrolls, padding 2px 18px). Each item is a 3-column row, margin-bottom 14px:
1. **Time rail** (width 42px, right-aligned, padding-top 11px): time 12px/700 `ink` over duration 10px `mute2` ("10:00" / "2h").
2. **Spine** (column, center, padding-top 11px): an 11px dot = type accent, with `2.5px #fff` border + `0 0 0 1.5px {accent}` ring; below it a 2px `#E6E8EE` connector filling the height.
3. **Card** (flex, `surface`, 1px `hairline`, radius 14px, padding 11px 12px, shadow `0 1px 2px rgba(12,14,22,.04)`): a header row gap 9px —
   - **Place types (Visit, Lodging):** a 40×40 radius-10 **photo thumbnail** (resolved place photo; gradient placeholder) with a small 18×18 radius-6 **type-accent badge** bottom-right (`2px #fff` border, white 11px icon). *POI thumbnail — only place types get a photo.*
   - **Transport types (Flight, Train, Transfer):** a 40×40 radius-10 **accent-tint icon tile** with the 19px type icon in accent. *No photo exists — keep the column honest.*
   - Then title 14px/700 (ellipsis) + meta 11.5px `slate` (ellipsis).

**RSVP (inline, when present):** below the header, separated by a 10px top border `#F2F3F6`: an avatar stack (three 22px circles, type-colored initials, `2px #fff` border, -7px overlap) + "3 going" 11px `slate`, then right-aligned **Going / Maybe** chips (11px/700, padding 5px 11px, radius 999px). Active chip = coral bg + white; inactive = `#F0F1F4` bg + `slate`. Tapping sets state.

**Distance gap pill (when present, between two located stops):** a quiet pill on the spine row — inline-flex gap 5px, 10.5px/600 `mute2`, `surface` bg, 1px `hairline` border, padding 3px 9px, radius 999px, leading mode icon (`directions_walk`/`directions_car`/`directions_boat`) 14px `#b3b7c0` — e.g. "400 m · 6 min walk". **Hidden around a Transfer/Flight** (that leg already is the travel).

**Empty day:** centered `event_available` 40px `borderDash`, "Nothing planned yet" 14px/600 `slate`, "Add a visit, transfer, or stay for this day." 12px.

Footer: lime **Add to plan** button (standard) with leading `add` 20px.

---

## Why it's coherent (carry verbatim)
- **Same type accents** — Visit coral, Train teal, Flight cyan, Transfer orange, Lodging plum, Other gray — as the spine dot + tinted icon. Lime stays on the add button only.
- **Time-rail timeline grouped by day.** Times quiet on the left; untimed items sort to the end of the day. Day pills scroll the trip's dates.
- **POI thumbnail** for place types (Visit & Lodging) with a small type-color badge; transport keeps its icon tile so the column stays honest and scannable.
- **Distance between stops** as a quiet spine pill — only between two located stops, hidden around a Transfer/Flight.
- **RSVP inline** (Going/Maybe) lives on the item, not a separate screen.
- **Feeds the moat:** a placed Visit shows here and as a Trip Map pin — one entry, three surfaces (Plan, Map, Wrapped).
- "Add to plan" opens the refined type-picker sheet (`09`/`11`); saving drops the item on the selected day.
