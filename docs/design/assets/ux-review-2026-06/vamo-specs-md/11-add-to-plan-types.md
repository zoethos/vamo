# Implementation Prompt — Add to Plan, the other types · screens 11 & 12

**For:** Codex / Claude Code · **Stack:** Flutter + M3 · **Source of truth:** `Vamo Add-to-Plan Types.dc.html` (5 frames: Flight, Train, Transfer, Lodging, Other). Screen 12 = the Flight **resolved** state. Tokens & rules: `_DESIGN-TOKENS.md`. Match pixel-for-pixel.

**Shared shell (all types):** same as the Visit sheet (`09`). App bar = `close` 24px + two-line title ("Add to plan" 16px/800 over "Amalfi Coast · Day N" 11px `slate`). A 3-col type picker grid (gap 8px, tiles padding 11px 0, radius 13px, icon tile 32×32; label 10.5px/700) sits at top with the current type selected in its accent. Body padding 18px. Pinned standard lime CTA whose label names the type ("Add flight", "Add train", …). **Only the fields that type needs appear; one accent per type.**

---

## FLIGHT — resolve by flight number  (accent: sky `#21B7D7`)

**Unresolved state (screen 11):**
- Label row: "Flight number" 13px/700 + "Flight" 11px/600 sky. Field: 1.5px sky border + `0 0 0 3px #21B7D71A`, leading `flight` 20px sky, value "TP 542", trailing `cancel` 19px `mute2`.
- `MATCHING FLIGHTS` label (10px/700 `slate`, .05em, margin 14px 0 7px). A results card (1px `hairline`, radius 13px, shadow `0 6px 18px rgba(12,14,22,.06)`). Each result row padding 11px 12px gap 11px: a 36×36 radius-9 **sky-tint** tile with the airline code (e.g. "TP") 11px/800 `#1f93b0`; "{code} · {airline}" 13.5px/700 + "{route} · {date}" 11px `slate`; trailing `chevron_right` 18px `#c4c8d0`. Rows divided 1px `#F0F1F4`.
- Footnote row: `info` 17px + "No number? Search by route instead." 11.5px `mute2`.
- CTA label "Pick a flight".

**Resolved state (screen 12)** — tapping a result swaps the body to a **boarding-pass card**: 1.5px sky border, radius 16px.
- Header strip (bg `#21B7D70F`, bottom 1px `#E2EEF2`, padding 10px 13px): 34×34 radius-8 **sky** tile + airline code white 11px/800; "{airline}" 13.5px/700 + "{code} · {aircraft}" 11px `slate`; trailing "Change" 11px/700 `#1f93b0` (resets).
- Route block (padding 16px 14px 12px): left dep time 24px/800 + airport code 14px/700 + terminal 10.5px `mute2`; center duration 10px `slate` over a connector (sky dot → gradient line → `flight` 17px sky); right arr time/code/terminal right-aligned.
- Footer strip (top 1px `#F0F1F4`, padding 9px 14px): `event` 16px sky + "{date} · {fromName} → {toName}" 11.5px `slate`.
- Below the card: two optional fields in a row (gap 9px) — Seat (`airline_seat_recline_normal`) flex 1, Booking ref (`confirmation_number`) flex 1.4.
- CTA label "Add flight".
- Flight data demo: TP 542 (TAP, NAP→LIS, 10:20→12:25, 2h05, A320, Mon May 12) and TP 544 (NAP→OPO, 14:05→16:20, E190).

---

## TRAIN — stations & times  (accent: jadeBright `#00C2A8`)
- A from→to station pair, vertically connected by a `more_vert` rail glyph. **Departure** field active: 1.5px `#00C2A8` border + `0 0 0 3px #00C2A81A`, leading 10px **jadeBright** dot, "Napoli Centrale", trailing `check_circle` 18px jade. **Arrival** field empty: leading 10px **coral** dot, "Arrival station" `mute2`, trailing `search` `mute2`.
- Times row (gap 9px): DEPARTS (label 10px/700 `slate`) → field `schedule` 18px jade + "09:40"; ARRIVES → field `schedule` `mute2` + "—".
- Details row (gap 9px): Train no. (`tag`) flex 1.3, Coach (`event_seat`) flex 1 — both placeholder `mute2`.
- Footnote: `bolt` 17px + "Have a train number? We'll fill the times." 11.5px `mute2`.
- CTA "Add train". Pattern: **from/to + departs/arrives + optional number that auto-fills times.** (Departure-dot = jade, arrival-dot = coral, everywhere.)

---

## TRANSFER — pick a mode  (accent: orange `#FF8A3D`/`#FFA766`)
- `MODE` label, then a wrap of **mode chips** (gap 7px): Car / Taxi / Ferry / Bus / Walk. Chip: inline-flex gap 5px, 12px/600, padding 7px 12px, radius 999px, 1px border. Selected: orange border, `#FF8A3D18` bg, `#d9701f` text. Unselected: `border`/`surface`/`slate`. Live — tapping changes the third field's label.
- Pick-up field (jade dot, `my_location` trailing) over Drop-off field (coral dot, `search` trailing).
- Times row: time field `schedule` 18px **orange** + "14:30" (flex 1); third field `confirmation_number` (flex 1.3) whose placeholder follows the mode — Car→"Plate / provider", Taxi→"Provider", Ferry→"Operator", Bus→"Line / operator", Walk→"Route note".
- CTA "Add transfer".

---

## LODGING — find a stay  (accent: plum `#6A2D6F`)
- "Stay" label + "Lodging" 11px/600 plum. Search field: 1.5px plum border + `0 0 0 3px #6A2D6F1A`, `search` 20px plum, "Hotel Marina Riviera", trailing `cancel`.
- A selected-result card (1px `hairline`, radius 13px, padding 9px 11px, margin-top 8px): 42×42 radius-10 gradient thumb `linear-gradient(135deg,#7a4fb5,#3a1d49)` + name 13.5px/700 + "address · ★ 4.6" 11px `slate` (ellipsis) + trailing `check_circle` 19px plum.
- Check-in / nights / check-out row (align flex-end): CHECK-IN field (`login` 17px plum, "May 12"); "2 nts" 11px/700 `mute2` between; CHECK-OUT field (`logout` 17px `mute2`, "May 14"). Labels 10px/700 `slate`.
- Booking confirmation field (`confirmation_number`, placeholder).
- CTA "Add lodging".

---

## OTHER — anything else  (accent: neutral `slate`)
- "What is it?" label + a free-text field active with a **neutral** focus ring (1.5px `#9aa0ac` + `0 0 0 3px rgba(122,128,144,.12)`), leading `edit` 20px `slate`, "Cooking class".
- Optional place field (`place`, "Add a place", "optional").
- Date/time row (gap 9px): `calendar_today` + "May 15"; `schedule` + "Time" placeholder.
- A notes box: 1.5px `border`, radius 13px, height 70px, "Add a note (optional)" 13px `mute2`.
- CTA "Add to plan".

---

## Principle (carry verbatim)
Each type keeps the same shell — type-picker, **one accent per type**, pinned lime CTA — but shows only the fields that type needs. Flight resolves by flight number (type/tap a flight → everything auto-fills); Train and Transfer follow the from→to + optional-reference-that-autofills pattern. The accent threads through every emphasis on the screen.
