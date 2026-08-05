# Implementation Prompt — New Trip (AI-assisted) · screen 16

**For:** Codex / Claude Code · **Stack:** Flutter + M3 · **Source of truth:** `Vamo New Trip.dc.html` (frames 1 & 2). Tokens & rules: see `_DESIGN-TOKENS.md`. Match the standalone HTML pixel-for-pixel.

Two-frame flow: (1) the **form** — name + AI destination resolver + date scroller; (2) the **AI plan** — tickable proposed stops. AI drafts; "start empty" always escapes.

---

## FRAME 1 — New trip form

App bar: leading `close` 24px, title **"New trip"** 18px/800.
Body padding 18px (horizontal). Section labels are 11px/700 `slate`, letter-spacing .04em, margin-bottom 6px.

**Trip name.** Label `TRIP NAME`. A standard field (1.5px `border`, radius 13px, padding 13px) with leading `edit` 20px `mute2` + value text 15px/600 ("Summer on the Amalfi Coast"). Margin-bottom 16px.

**Destination (AI-resolved).** Label row, space-between: `DESTINATION` left; an **AI-resolve chip** right — inline-flex, gap 4px, 10.5px/800 `plum`, bg `linear-gradient(90deg,#F3E9FA,#FBEEF3)`, 1px `#E6D9EE` border, padding 3px 9px, radius 999px, leading `auto_awesome` 14px + "AI resolve".
- Search field, **focused state**: 1.5px `plum` border + `box-shadow:0 0 0 3px #6A2D6F1A`. Leading `search` 20px `plum`, query text 15px (with a `plum` caret), trailing `auto_awesome` 19px `plum`.
- **Suggestion dropdown** (appears under field): `surface`, 1px `hairline` border, radius 13px, shadow `0 6px 18px rgba(12,14,22,.06)`. Each row: padding 10px 12px, gap 11px; 34×34px radius-9 gradient thumbnail with a white 18px MSO icon centered; name 13.5px/600 + meta 11px `mute`; selected row tinted `#6A2D6F0D` and shows a trailing `check_circle` 19px `plum`. Rows 1–2 have a 1px `#F0F1F4` bottom divider.
- Demo options: `Amalfi` (Town · Salerno, gradient coral→plum, `place`), `Amalfi Coast` (Region · Campania, orange→coral, `landscape`), `Amalfi (Positano area)` (Area · 16 km west, jadeBright→sky, `beach_access`). **Resolving a destination unlocks the AI plan button.**

**Dates.** Label `DATES` (margin-top 16px). A tappable row (standard field style, cursor pointer): leading `calendar_month` 20px `coral`; value 15px/600 (`May 12 – 18`, or "Add dates" in `mute2` when empty); trailing duration 12px/700 `mute2` ("6 days"). Tapping opens the **date sheet** (see `17-date-scroller.md` — this is the same control as a bottom-sheet overlay).

Footer: the **AI plan CTA**, full width. **Enabled** (destination resolved): lime fill, ink text, shadow — label "Draft my plan with AI", leading `auto_awesome` 20px. **Disabled** (not resolved): bg `segBg`, text `mute2`, no shadow, label "Resolve a destination first". Below, centered 11px `mute2`: "or **start empty** — add stops yourself" ("start empty" in 700 `slate`).

### Date sheet overlay (opened from Dates)
Scrim `rgba(12,14,22,.42)`. Sheet bottom-anchored, `surface`, top radius 22px, padding 16px, shadow `0 -10px 30px rgba(0,0,0,.18)`. Grabber 38×4px `border`. Header row: "When?" 16px/800 + live summary 12px/700 `plum` ("May 12 – 18 · 6 days"). Then the horizontal month/day carousel + opt-in times toggle + lime confirm — **identical mechanism to the standalone Date Scroller; build once and reuse** (full spec in `17-date-scroller.md`). Confirm label "Use May 12 – 18".

---

## FRAME 2 — AI plan proposal

App bar replaced by a **resolved-destination hero**, 130px tall: gradient backdrop `linear-gradient(135deg,#FF5B4D,#FFA766 55%,#6A2D6F)` (in production this is the AI-pulled place photo) with a top scrim `linear-gradient(to top,rgba(12,14,22,.66),transparent 62%)`. Overlays: `arrow_back` 22px white top-left; an "**AI backdrop**" pill top-right (10px/800 white, bg `rgba(12,14,22,.4)`, padding 4px 9px, radius 999px, leading `auto_awesome` 13px); bottom-left title "Summer on the Amalfi Coast" 19px/800 white + subtitle "Amalfi, Italy · May 12–18 · 6 days" 11.5px white/.92.

**AI intro row** (padding 11px 16px 8px): `auto_awesome` 18px `plum` + text 12.5px `inkSoft`: "AI found **{N} stops** worth visiting. Keep what you like — skip the rest."

**Kept counter row** (padding 2px 16px 8px): left "{kept} of {total} kept" 11px/700 `slate`; right a tappable "Keep all"/"Skip all" toggle 11.5px/700 `plum`.

**Stop list** (scrolls, padding 0 12px), grouped by day. Day label: 10px/800 `mute`, letter-spacing .06em, padding 8px 6px 5px ("Day 1 · May 12").
- **Stop row** (tappable to keep/skip): gap 11px, align center. Leading 36×36px radius-10 tile + 18px MSO icon. Body: name 13.5px/700 (ellipsis) + meta 11px `mute` (ellipsis). Trailing 24×24px round check.
  - **Kept:** tile bg = type accent, icon white; row at full opacity; check bg `jade`, icon `check`.
  - **Skipped:** tile bg = accent tint, icon = accent; row + body opacity 0.5; check `surface` with 1.5px `borderDash` border, icon `add`.
- Demo stops carry types: Check-in (lodging/plum `bed`), Piazza Duomo (visit/coral `place`), Path of the Gods hike (visit `hiking`), Lunch (transfer-ish orange `restaurant`), Ferry (orange `directions_boat`), Villa Rufolo (visit `local_florist`).

Footer CTA (lime): label "Create trip · {kept} stops" — or "Create empty trip" if none kept. Kept stops populate the Plan as typed items, fully editable later.

---

## Behavior & rationale (carry verbatim)
- **AI destination resolver** turns free text into a real place (lat/lng, region) + backdrop — same engine as POI place-info, reused. Resolving unlocks the plan.
- **Booking-style date scroller** — tap once = single-day, tap a second = range; times opt-in.
- **AI plan of stops** — proposed known places grouped by day; user ticks to keep/skip; kept become editable Plan items.
- **Naming:** call each itinerary entry a **"stop"** in UI copy ("12 stops") — covers visits/meals/breaks without jargon.
- **Escape hatch:** "Start empty" always skips AI. Lime stays on the single primary action.
- **Guardrail:** resolution/enrichment is server-side, lazy, on demand — never a call per keystroke.
