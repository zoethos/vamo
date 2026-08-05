# Implementation Prompt — New Trip → Advanced Travel (travel legs) · screen 18

**For:** Codex / Claude Code · **Stack:** Flutter + M3 · **Source of truth:** `Vamo New Trip Advanced Travel.dc.html` (frames 1 & 2). Tokens & rules: `_DESIGN-TOKENS.md`. Match the standalone HTML pixel-for-pixel.

> The previous build was rejected for diverging from the mockup. Build *exactly* what's below — no Material defaults bleeding through, no extra cards, no gradient fills.

**Mode color map (this view):** Car `#FF8A3D` `directions_car` · Motorbike coral `#FF5B4D` `two_wheeler` · Bike jade `#00A892` `pedal_bike` · Train jadeBright `#00C2A8` `train` · Flight sky `#21B7D7` `flight` · Bus plum `#6A2D6F` `directions_bus`. Mode tint = mode color + `18` hex alpha (used for selected chip bg and the leg icon tile).

---

## The constraint model (this is the product — preserve verbatim)
Advanced Travel is a **gated power-user mode** (off by default; default New Trip is name · destination · dates). Model:
```
TravelPlan { advanced: bool; modes: Set<ModeId>; legs: List<TravelLeg> (ordered) }
TravelLeg { id; modeId; window: DateRange; reach: ReachLimit }
ReachLimit = Distance(value:int 9999==No limit/∞, unit 'km'|'mi') | Time(hoursPerDay:int)
```
- **A leg = mode · window (dates/times you're free) · reach (max km — or hours/day).** e.g. `Car · Jul 1–3 · ≤ 600 km` → `Train · Jul 4–7 · ≤ 5h/day`.
- You don't draw the route — you give AI the **envelope of what's possible**; it solves a valid itinerary inside it.
- **Legs are ordered & chainable**; AI sequences stops so each hop respects the leg covering those dates.
- **AI is optional and drafts, never gatekeeps** — manual ("I'll plan it myself") sits beside the AI CTA, equal weight.
- **Live feasibility** flags conflicts before planning ("120 km by bike on Jul 5 exceeds your 80 km cap").

---

## FRAME 1 — New trip → Travel (advanced)
App bar: `close` 24px + "New trip" 18px/800. Body padding 16px.

**Collapsed context row:** two equal cards (gap 9px), each `surface`, 1px `hairline`, radius 12, padding 9px 11px — a 10px/800 `slate` label over a 13px/700 value. DESTINATION → "Amalfi Coast"; DATES → "Jul 1 – 7".

**Advanced toggle:** full-width tappable row, padding 13, radius 14, gap 11, **1.5px** border (`plum` ON / `border` OFF), bg `#FBF7FE` ON / `surface` OFF. Leading `tune` 21px plum; middle = "Plan how you'll travel" 14px/800 + an `ADVANCED` pill (9px/800 plum, bg `#F1E6F8`, 1px `#E6D9EE`, radius 999) above subtitle "Multi-modal legs & limits for AI to solve" 11px `#8a93a0`; trailing = the standard switch (track 40×23, knob 19, plum track when ON).

**Everything below renders only when `advanced == true`:**
- **`MODES YOU'LL USE`** — a wrap of mode chips (gap 8), **multi-select**. Chip: inline-flex gap 6, 12px/700, padding 8px 12px, radius 999, 1.5px border. Selected: mode-color border, mode tint bg, `inkSoft` text. Unselected: `border`/`surface`/`mute2`. Leading 17px mode icon. Default ON: Car + Train.
- **`TRAVEL LEGS`** header (+ "in order" 10px/700 `mute2` right). A vertical list (gap 9) of **leg rows** (tappable → Frame 2): gap 11, padding 10px 12px, `surface`, 1px `hairline`, radius 13, shadow `0 1px 2px rgba(12,14,22,.04)`. Leading 38×38 radius-10 tile (mode tint) + 20px mode icon (mode color); body = mode name 13.5px/700 over "{window} · {reach}" 11px `#8a93a0` (single line, ellipsis); trailing `chevron_right` 18px `#c4c8d0`. Demo: `Car · Jul 1 – 3 · ≤ 600 km`, `Train · Jul 4 – 7 · ≤ 5h / day`. Last item = **add-leg row**: dashed 1.5px `borderDash`, radius 13, `plum` `add` 19px + "Add a travel leg" 13px/700.
- **Feasibility banner:** gap 9, padding 11px 12px, radius 12. OK = bg `feasGreenBg`, 1px `feasGreenBd`, `verified` 18px `feasGreenFg` + text 11.5px `inkSoft`: "Feasible — AI can connect 8 stops across your 2 legs within the Jul 1–7 range." (Conflict = warning icon/color, same layout.)

**Footer (pinned):** primary lime CTA "Draft route with AI" (leading `auto_awesome` 20px) with a floating `★ VAMO AI` badge (top:-9 right:12, 9px/800 white on plum). Below: secondary button "I'll plan it myself" (`surface`, 1.5px `borderDash`, radius 14, `inkSoft` 14px/700, leading `edit_note` 19px `slate`), then centered microcopy 10.5px `mute2`: "AI is optional — it drafts, you decide. Build by hand anytime."

---

## FRAME 2 — Travel leg editor (window + reach limit)
App bar: `arrow_back` 24px + "Travel leg" 17px/800 + trailing destructive "Remove" 12px/700 `#D7402F`. Body padding 18px.

- **`MODE`** — a wrap of mode chips, **single-select** (unselected text `slate` here). Sets the leg's mode.
- **`WHEN YOU CAN TRAVEL`** — a field row (1.5px `border`, radius 13, padding 12px 13px): `calendar_month` 20px coral + value "Jul 1 – Jul 3" 14px/700 + duration "3 days" 11px/700 `mute2`. **Tapping opens the Date Scroller bottom sheet (`17-date-scroller.md`).** Helper below: `schedule` 17px jade + "Times optional — leave open for flexibility" 12px `slate`.
- **`REACH LIMIT`** header + a **Distance / Time segmented control** (track `segBg`, radius 9, padding 2; selected = `ink`+white, idle `slate`).
  - **Distance (default):** centered big number 38px/800 + " km" 16px/700 `mute` (∞ when "No limit"), caption "max you'll cover by {mode} on this leg" 11px `mute2`. Preset chips (h-scroll, gap 7): `100 km`, `300 km`, `600 km`, `No limit` (=9999). Chip 12px/700, padding 9px 14px, radius 11; selected `ink`+white, idle `chipBg`+`inkSoft`.
  - **Time:** same block, suffix "h / day", caption "max time you'll spend moving". Chips: `2h 4h 5h 8h`.
- Footnote 10.5px `mute2`: "Units follow your profile · **{unit}** · change in Profile › Preferences".

**Footer (pinned):** full-width lime **"Save leg"** (standard). Writes the leg back and returns to Frame 1.

## Acceptance
Advanced gates everything below the toggle · mode chips multi on F1 / single on F2 · leg icon tile = mode tint bg + mode-color icon · lime exactly once per screen · ★ VAMO AI badge + equal-weight manual path · reach ∞ for "No limit", unit from profile · every radius/padding/size matches.
