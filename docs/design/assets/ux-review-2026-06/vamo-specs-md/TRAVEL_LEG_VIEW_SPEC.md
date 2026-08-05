# Implementation Prompt — Advanced Travel & Travel Leg view (+ Date Scroller addendum)

**For:** Codex / Claude Code · **Stack:** Flutter + Material 3 (Android-first, locked brand palette over Material You)
**Source of truth:** `Vamo New Trip Advanced Travel.dc.html` (frames 1 & 2) and `Vamo Date Scroller.dc.html`. Open the standalone HTML and match it pixel-for-pixel. This doc is the literal spec — do not improvise layout, spacing, or color. If a value isn't here, read it off the mockup, don't invent it.

> **Why the previous attempt was rejected:** it diverged from the mockup. Build *exactly* what's below. Every padding, radius, font size, and hex is intentional. No Material defaults bleeding through, no extra cards, no rounded-corner-with-left-border tropes, no gradient fills.

---

## 0. Brand tokens (use these names; do not hardcode elsewhere)

```
ink            #0C0E16   // primary text, selected fills, dark seg buttons
inkSoft        #2A2E3A   // body text
slate          #6b7280   // secondary text / muted icons
mute           #8a93a0   // captions
mute2          #9aa0ac   // faint captions, "in order"
lime           #C6FF00   // THE primary action color — fill only, one per screen
plum           #6A2D6F   // "Advanced" brand accent, bus mode
coral          #FF5B4D   // dates / calendar / range tint
jade           #00A892   // times / bike
jadeBright     #00C2A8   // train
sky            #21B7D7   // flight
carOrange      #FF8A3D   // car
surface        #FFFFFF
appBg          #FAFAFB   // screen background inside the phone
hairline       #ECEDF1   // card borders
border         #E2E4EA   // input borders
borderDash     #d7dae0   // dashed "add" border + secondary button border
chipBg         #F1F2F5   // unselected chips
segBg          #EEF0F4   // segmented-control track
feasGreenBg    #E2F6EC   // feasibility ok background
feasGreenBd    #BFE8D2
feasGreenFg    #1f8f5e
```

Fonts: system (`-apple-system / Roboto`) for text; **Material Symbols Outlined** for all icons. Use `Icons` equivalents in Flutter (mapping in §4).

Mode color map (single source — used by chips, leg rows, leg icon tiles):

| id | name | icon (MSO) | color |
|---|---|---|---|
| `car` | Car | `directions_car` | `carOrange #FF8A3D` |
| `motorbike` | Motorbike | `two_wheeler` | `coral #FF5B4D` |
| `bike` | Bike | `pedal_bike` | `jade #00A892` |
| `train` | Train | `train` | `jadeBright #00C2A8` |
| `flight` | Flight | `flight` | `sky #21B7D7` |
| `bus` | Bus | `directions_bus` | `plum #6A2D6F` |

Mode tint = mode color + `18` hex alpha (≈ 9% opacity) — used for selected chip background and leg icon tile background.

---

## 1. The data model (what AI consumes)

Advanced Travel is a **gated power-user mode**. Default New Trip is just name · destination · dates. Flipping the Advanced toggle unlocks multimodal planning. Model:

```
TravelPlan {
  advanced: bool                 // default false in production; toggle unlocks the rest
  modes: Set<ModeId>             // which modes this trip may use (multi-select)
  legs: List<TravelLeg>          // ORDERED & chainable
}

TravelLeg {
  id
  modeId: ModeId
  window: DateRange              // dates (+ optional times) the traveler is free
  reach: ReachLimit              // the cap AI must respect on this leg
}

ReachLimit = Distance(value:int, unit:'km'|'mi')   // value 9999 == "No limit" (∞)
           | Time(hoursPerDay:int)
```

Semantics to preserve verbatim — these are the product, not flavor text:
- **A leg = mode · window (dates/times you're free) · reach (max km — or hours/day).** e.g. `Car · Jul 1–3 · ≤ 600 km` → `Train · Jul 4–7 · ≤ 5h/day`.
- **You don't draw the route.** The user gives AI the *envelope of what's possible*; AI solves a valid itinerary inside it.
- **Legs are ordered & chainable.** AI sequences stops so each hop respects the leg whose window covers those dates.
- **AI is optional and drafts, never gatekeeps.** Manual ("I'll plan it myself") sits beside the AI CTA, equally valid.
- **Live feasibility** checks the envelope and flags conflicts *before* planning (e.g. "120 km by bike on Jul 5 exceeds your 80 km cap").

---

## 2. FRAME 1 — New trip → Travel (advanced)

A full screen inside the New-trip flow. Top app bar, scrollable body, pinned footer with two buttons.

### App bar
- Leading `close` icon (24px). Title **"New trip"** — 18px / weight 800, ink. No elevation, sits on `appBg`.

### Body (scrolls; hide scrollbar). Horizontal page padding 16px.

**2.1 Collapsed context row** (read-only summary of earlier steps). Two equal cards in a row, gap 9px, margin-bottom 14px. Each card: `surface` bg, 1px `hairline` border, radius 12px, padding 9px 11px.
- Card content: a label (10px / weight 800 / `slate` / letter-spacing .05em / uppercase) above a value (13px / weight 700, margin-top 3px).
- Card A → `DESTINATION` / **Amalfi Coast**. Card B → `DATES` / **Jul 1 – 7**.

**2.2 Advanced toggle** (the gate). A full-width tappable row, padding 13px, radius 14px, gap 11px, centered vertically.
- Border: **1.5px**; color `plum` when ON, `border` when OFF. Background `#FBF7FE` when ON, `surface` when OFF.
- Leading icon `tune` 21px, `plum`.
- Middle (flex): title row = **"Plan how you'll travel"** (14px / weight 800) + an `ADVANCED` pill inline (9px / weight 800 / `plum` text / bg `#F1E6F8` / 1px border `#E6D9EE` / padding 2px 7px / radius 999px / gap 7px from title). Subtitle below (11px / `#8a93a0` / margin-top 2px): "Multi-modal legs & limits for AI to solve".
- Trailing: a switch. Track 40×23px, radius 999px, padding 2px, knob 19×19px white circle with `0 1px 3px rgba(0,0,0,.25)` shadow. Track bg `plum` + knob right when ON; `borderDash` + knob left when OFF.

**Everything below 2.2 is rendered only when `advanced == true`** (animate in, don't jank the layout).

**2.3 Modes you'll use.** Section label (`MODES YOU'LL USE`, the 10px/800/slate label style, margin 18px 0 8px). Then a **wrap** of mode chips, gap 8px.
- Chip: inline-flex, gap 6px, font 12px / weight 700, padding 8px 12px, radius 999px, **1.5px** border.
- Selected: border = mode color, bg = mode tint, text `inkSoft`. Unselected: border `border`, bg `surface`, text `mute2`.
- Leading 17px MSO icon (the mode icon) + name. Tapping toggles membership in `modes`. Multi-select.
- Default selected for the mockup: Car + Train ON; others OFF.

**2.4 Travel legs.** Header row (space-between, margin 18px 0 8px): label `TRAVEL LEGS` left; `in order` right (10px / weight 700 / `mute2`). Then a vertical list, gap 9px.
- **Leg row** (tappable → opens Frame 2 for that leg): flex row, gap 11px, align center, padding 10px 12px, `surface` bg, 1px `hairline` border, radius 13px, shadow `0 1px 2px rgba(12,14,22,.04)`.
  - Leading icon tile: 38×38px, radius 10px, bg = mode tint; centered 20px MSO mode icon in mode color.
  - Middle (flex, min-width 0): line 1 = mode name (13.5px / weight 700); line 2 = `{window} · {reach}` (11px / `#8a93a0`, single line, ellipsis-truncated).
  - Trailing: `chevron_right` 18px, `#c4c8d0`.
  - Mockup legs: `Car · Jul 1 – 3 · ≤ 600 km` and `Train · Jul 4 – 7 · ≤ 5h / day`.
- **Add-leg row** (last item): dashed **1.5px** `borderDash` border, radius 13px, padding 11px 12px, gap 9px, `plum` content: `add` icon 19px + "Add a travel leg" (13px / weight 700). Tapping appends a new leg and opens Frame 2.

**2.5 Feasibility banner.** Margin-top 14px. Flex row, gap 9px, padding 11px 12px, radius 12px. OK state: bg `feasGreenBg`, 1px `feasGreenBd` border, `verified` icon 18px in `feasGreenFg`, then text (11.5px / line-height 1.4 / `inkSoft`): "Feasible — AI can connect 8 stops across your 2 legs within the Jul 1–7 range." (Conflict state would swap to a warning icon/color and the conflict copy — same layout.)

Add 14px of bottom spacer after the feasibility banner before the footer.

### Footer (pinned, not scrolling). Padding 8px 16px 16px.
- **Primary CTA** — full width, `lime` fill, `ink` text, no border, radius 14px, 15px / weight 800, vertical padding 15px, shadow `0 6px 16px rgba(198,255,0,.4)`. Content centered, gap 8px: `auto_awesome` icon 20px + label **"Draft route with AI"** (label is "Draft my plan with AI" when advanced is off). A `★ VAMO AI` badge floats at top:-9px right:12px — 9px / weight 800 / white text / `plum` bg / padding 2px 9px / radius 999px / shadow `0 2px 6px rgba(106,45,111,.4)`.
- **Secondary button** — margin-top 9px, full width, `surface` bg, **1.5px** `borderDash` border, radius 14px, `inkSoft` text 14px / weight 700, vertical padding 13px. Content centered, gap 8px: `edit_note` icon 19px in `slate` + "I'll plan it myself".
- **Microcopy** centered below, margin-top 8px, 10.5px / `mute2`: "AI is optional — it drafts, you decide. Build by hand anytime."

> The lime button is the screen's single primary action. The "plan it myself" path must read as equally legitimate, never disabled or de-emphasized into invisibility.

---

## 3. FRAME 2 — Travel leg editor (window + reach limit)

Opened by tapping a leg row or "Add a travel leg". Top app bar, scroll body, pinned Save footer.

### App bar
- Leading `arrow_back` 24px. Title **"Travel leg"** 17px / weight 800 (flex). Trailing text action **"Remove"** 12px / weight 700 in `#D7402F` (destructive — confirm before deleting an existing leg).

### Body (scroll, hide scrollbar). Page padding 18px.

**3.1 Mode.** Label `MODE`. A wrap of mode chips, gap 8px, margin-bottom 18px — same chip spec as 2.3 but **single-select** (this leg's mode). Unselected text here is `slate` (not `mute2`). Tapping sets `editMode`.

**3.2 When you can travel.** Label `WHEN YOU CAN TRAVEL`.
- A field row: 1.5px `border`, radius 13px, padding 12px 13px, `surface` bg, gap 10px, align center, margin-bottom 8px. Leading `calendar_month` 20px in `coral`; value **"Jul 1 – Jul 3"** (14px / weight 700, flex); trailing duration **"3 days"** (11px / weight 700 / `mute2`).
- **Tapping this row opens the Date Scroller bottom sheet (§Addendum).** On confirm, write the range back into this field and the leg's `window`.
- Helper row below, gap 9px, 12px / `slate`, margin-bottom 18px: `schedule` icon 17px in `jade` + "Times optional — leave open for flexibility".

**3.3 Reach limit.** Header row, space-between, margin-bottom 8px: label `REACH LIMIT` left; a **segmented control** right — track bg `segBg`, radius 9px, padding 2px, two segments "Distance" / "Time" (11px / weight 700, padding 6px 12px, radius 7px). Selected segment: `ink` bg + white text; unselected: `slate` text, transparent.

**Distance mode** (default):
- Centered value block, padding 8px 0 12px: big number (38px / weight 800 / letter-spacing -.02em) + unit suffix (` km`, 16px / weight 700 / `mute`). When value is `9999` show **∞**. Caption below (11px / `mute2`, margin-top 2px): "max you'll cover by {mode} on this leg" ({mode} lowercased, live from selected mode).
- A horizontal scroll row of preset chips, gap 7px (hide scrollbar). Chip: flex:none, 12px / weight 700, padding 9px 14px, radius 11px. Selected: `ink` bg + white. Unselected: `chipBg` bg + `inkSoft`. Values: `100 km`, `300 km`, `600 km`, **"No limit"** (= 9999). Tapping sets `dist`.

**Time mode:**
- Same centered block: big number (38px / weight 800) + suffix "h / day" (16px / weight 700 / `mute`). Caption: "max time you'll spend moving".
- Preset chips (same chip style): `2h`, `4h`, `5h`, `8h`. Tapping sets `time`.

**3.4 Units footnote.** Margin-top 10px, 10.5px / `mute2`: "Units follow your profile · **{unit}** · change in Profile › Preferences". Unit comes from profile (`km`/`mi`); the distance presets and suffix follow it.

### Footer (pinned). Padding 10px 18px 16px.
- Single **Save leg** button — full-width `lime` fill, `ink` text, no border, radius 14px, 15px / weight 800, vertical padding 15px, shadow `0 6px 16px rgba(198,255,0,.4)`. Writes the leg back to the plan and returns to Frame 1.

---

## 4. Icon mapping (Material Symbols Outlined → Flutter Icons)

`close`→close · `tune`→tune · `add`→add · `chevron_right`→chevron_right · `verified`→verified · `auto_awesome`→auto_awesome · `edit_note`→edit_note · `arrow_back`→arrow_back · `calendar_month`→calendar_month · `schedule`→schedule · `directions_car`→directions_car · `two_wheeler`→two_wheeler · `pedal_bike`→pedal_bike · `train`→train · `flight`→flight · `directions_bus`→directions_bus · `straighten`→straighten · `route`→route.

---

# ADDENDUM — Date Scroller control (NOT YET IMPLEMENTED — build this)

Source: `Vamo Date Scroller.dc.html`. A booking-style **horizontal month/day scroller** in a bottom sheet. It's the shared date control: it powers the trip dates *and* each travel leg's window (Frame 2, §3.2) *and* the per-stop time in Add-to-Plan. Build it once, reuse everywhere — identical mental model.

### Container
Bottom sheet card: `surface` bg, top radius 24px, padding 18px 18px 20px, shadow `0 18px 50px rgba(12,14,22,.16)`, 1px `hairline` border. A grabber at top: 40×4px, radius 2px, `border` color, centered, margin-bottom 16px.

### 4a. Header + live summary
Row, align flex-end, space-between, margin-bottom 14px.
- Left: **"When?"** (19px / weight 800 / line-height 1.1) + subtitle "Single day or a range" (12px / `mute`, margin-top 2px).
- Right (right-aligned): summary main (15px / weight 800 / **coral**) over duration (11px / weight 600 / `mute`). Both update live as the user taps.

### 4b. Quick presets
Horizontal scroll row (hide scrollbar), gap 7px, padding-bottom 14px. Chip: flex:none, 12px / weight 700, padding 8px 13px, radius 999px, nowrap. Selected: `ink` bg + white. Unselected: `chipBg` bg + `#4a4f5b`.
Presets (each sets start+end in one tap): **This weekend**, **Next week**, **10 days**, **Just a day**.

### 4c. Month / day carousel  ← the core mechanism
Horizontal scroll (hide scrollbar), gap 20px between months, padding 2px 2px 6px, `scroll-snap-type: x proximity`.
- **Per month:** a sticky month label (`MAY 2026`, 11px / weight 800 / `slate` / letter-spacing .05em / margin-bottom 9px / sticky to left edge so it stays visible while scrolling that month). Below it, a row of day cells, gap 4px.
- **Day cell:** 46×58px, radius 13px, column layout, centered, gap 3px, `scroll-snap-align: start`, cursor pointer. Contents top→bottom: day-of-week letter (9px / weight 700 / opacity .65), day number (16px / weight 800 / line-height 1), and a 4px dot.
  - **Unselected:** bg `chipBg`, text `inkSoft`, transparent dot.
  - **In-range** (between start & end, exclusive): bg = `coral` at `1F` alpha (≈12%), text `ink`, transparent dot.
  - **Start or end edge:** bg `ink`, white text, **lime dot** (4px, `#C6FF00`) — the dot marks the two endpoints.
- Render real calendar weekdays. Mockup data: May 2026 from the 8th (May 1 = Friday, weekday index offset 4), then June 1–14 (June 1 = Monday). Use real month lengths; don't fake the day-of-week.
- Caption under carousel, centered, 10.5px / `mute2`, margin 8px 0 14px: "‹ scroll months · tap a day to start · tap another for the range ›".

### 4d. Selection logic (exact — match the state machine)
State: `{ start, end }` as absolute day indices (so cross-month ranges work). "Single" means `end == null || end == start`.
- **First tap** (currently single): if you tap the same day, stay single. If you tap a *later* day → that becomes `end` (range). If you tap an *earlier* day → it becomes the new `start` and the old start becomes `end` (they swap so start ≤ end).
- **Tap while a range exists** → start over: the tapped day becomes a fresh single day (`start = end = n`).
- Duration = `1` when single, else `abs(end-start)+1`. Summary main = single label (`May 12`) or `May 12 – 18` (range; second date drops the repeated month word).
- Any manual tap clears the active preset highlight.

### 4e. Add times toggle (opt-in)
A full-width row, padding 12px 13px, 1px `hairline` border, radius 13px, gap 11px. Bg `#F7FCFA` when ON, `surface` when OFF. Leading `schedule` 20px — `jade` when ON, `mute2` when OFF. Middle: "Add times" (14px / weight 700) + "Optional — most trips only need dates" (11px / `mute`). Trailing: same switch component as Frame 1, but ON track color is `jadeBright #00C2A8`.

**When ON, reveal time scrollers** (animate in):
- **START TIME** label (10px / weight 800 / `slate` / letter-spacing .05em / margin-bottom 7px). Horizontal scroll row, gap 6px, snap. Time pill: flex:none, padding 9px 13px, radius 11px, 13px / weight 700. Selected: `jade` bg + white. Unselected: `chipBg` + `inkSoft`. Times: `07:00 08:00 09:00 10:00 12:00 14:00 16:00 18:00 20:00`.
- **END TIME** — only shown when the date selection is a range (`showEndTime = !single`). Label "END TIME · optional" (the "· optional" in `#b0b6c0` / weight 600), margin 12px 0 7px. Same pill row/behavior.

### 4f. Confirm button
Full-width `lime` fill, `ink` text, no border, radius 14px, 15px / weight 800, vertical padding 15px, shadow `0 6px 16px rgba(198,255,0,.4)`, margin-top 16px.
Label is **dynamic**: single → "Use May 12"; range → "Use {N} days". When times are on and it's a single day, append " · {startTime}" (e.g. "Use May 12 · 09:00").

### Behavior summary (carry verbatim into code comments)
1. First tap = single-day trip (start = end); CTA reads "Use May 12".
2. Second tap extends to a range; tapping earlier than start flips them; a third tap starts over.
3. Times are opt-in — end date alone suffices for most trips; times stay collapsed until asked for.
4. Scroll, don't paginate — months flow inline with snap; "3 weeks out" is a flick, not taps through a grid.

---

## 5. Acceptance checklist (reviewer will diff against the mockup)

- [ ] Advanced is a single toggle; all of modes/legs/feasibility hide when off; default flow stays name·destination·dates.
- [ ] Mode chips: multi-select on Frame 1, single-select on Frame 2; selected = mode-colored 1.5px border + mode tint fill.
- [ ] Leg row icon tile uses mode tint bg + mode-color icon; subtitle is `window · reach`, truncated.
- [ ] Lime appears exactly once per screen (the primary CTA). Never decorative, never on small text.
- [ ] "★ VAMO AI" badge on the primary CTA; "I'll plan it myself" present and equal-weight.
- [ ] Reach limit: Distance/Time segmented control; big-number display; preset chips; ∞ for "No limit"; unit follows profile.
- [ ] Date Scroller: horizontal month scroll with sticky labels, ink endpoints + lime dots, coral in-range tint, exact tap state machine, opt-in times with jade pills, dynamic CTA label.
- [ ] No Material default surfaces leaking (no elevation shadows on app bars, no default switch styling, no purple ripples) — brand tokens only.
- [ ] All radii, paddings, and font sizes match the values in this doc.
