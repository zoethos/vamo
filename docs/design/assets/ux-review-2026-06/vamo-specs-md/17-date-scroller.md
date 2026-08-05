# Implementation Prompt — Date Scroller control · screen 17

**For:** Codex / Claude Code · **Stack:** Flutter + M3 · **Source of truth:** `Vamo Date Scroller.dc.html`. Tokens & rules: `_DESIGN-TOKENS.md`. **Status: not yet implemented — build this.** Match the standalone HTML pixel-for-pixel.

A booking-style **horizontal month/day scroller** in a bottom sheet. It is the shared date control: it powers the trip dates (New Trip, `16`), each travel leg's window (Advanced Travel Frame 2, `18`), and the per-stop time in Add-to-Plan. **Build once, reuse everywhere** — identical mental model.

---

## Container
Bottom sheet: `surface`, top radius 24, padding 18px 18px 20px, shadow `0 18px 50px rgba(12,14,22,.16)`, 1px `hairline`. Grabber at top: 40×4, radius 2, `border`, centered, margin-bottom 16.

## a · Header + live summary
Row, align flex-end, space-between. Left: "When?" 19px/800 (line-height 1.1) + "Single day or a range" 12px `mute`. Right (right-aligned): summary main 15px/800 **coral** over duration 11px/600 `mute`. Both update live as the user taps.

## b · Quick presets
H-scroll row (hide scrollbar), gap 7, padding-bottom 14. Chip: flex:none, 12px/700, padding 8px 13px, radius 999, nowrap; selected `ink`+white, idle `chipBg`+`#4a4f5b`. Presets (each sets start+end in one tap): **This weekend · Next week · 10 days · Just a day**.

## c · Month / day carousel  ← the core mechanism
H-scroll (hide scrollbar), gap 20 between months, padding 2px 2px 6px, `scroll-snap-type:x proximity`.
- **Per month:** a **sticky** month label (`MAY 2026`, 11px/800 `slate`, .05em, margin-bottom 9, sticky to the left edge while scrolling that month). Below, a row of day cells, gap 4.
- **Day cell:** 46×58, radius 13, column, centered, gap 3, `scroll-snap-align:start`, pointer. Top→bottom: weekday letter 9px/700 (opacity .65), day number 16px/800 (line-height 1), a 4px dot.
  - **Unselected:** bg `chipBg`, text `inkSoft`, transparent dot.
  - **In-range** (between start & end, exclusive): bg `coral` at `1F` alpha, text `ink`, transparent dot.
  - **Start/end edge:** bg `ink`, white text, **lime 4px dot** — the dot marks the two endpoints.
- Use **real calendar weekdays** (don't fake the day-of-week). Mockup data: May 2026 from the 8th (May 1 = Friday), then June 1–14 (June 1 = Monday).
- Caption under carousel, centered, 10.5px `mute2`, margin 8px 0 14px: "‹ scroll months · tap a day to start · tap another for the range ›".

## d · Selection logic (exact state machine)
State `{ start, end }` as absolute day indices (so cross-month ranges work). "Single" = `end == null || end == start`.
- **First tap** (single): same day → stay single; a *later* day → becomes `end` (range); an *earlier* day → becomes new `start`, old start becomes `end` (swap so start ≤ end).
- **Tap while a range exists** → start over: tapped day becomes a fresh single (`start = end = n`).
- Duration = 1 (single) else `abs(end-start)+1`. Summary main = `May 12` (single) or `May 12 – 18` (range; second date drops the repeated month word). Any manual tap clears the active preset highlight.

## e · Add-times toggle (opt-in)
Full-width row, padding 12px 13px, 1px `hairline`, radius 13, gap 11; bg `#F7FCFA` ON / `surface` OFF. Leading `schedule` 20px — jade ON / `mute2` OFF. Middle: "Add times" 14px/700 + "Optional — most trips only need dates" 11px `mute`. Trailing: the standard switch, ON track **jadeBright `#00C2A8`**.

**When ON, reveal time scrollers** (animate in):
- **START TIME** label (10px/800 `slate`, .05em). H-scroll row, gap 6, snap. Time pill: flex:none, padding 9px 13px, radius 11, 13px/700; selected `jade`+white, idle `chipBg`+`inkSoft`. Times: `07:00 08:00 09:00 10:00 12:00 14:00 16:00 18:00 20:00`.
- **END TIME** — shown only when the date selection is a range (`showEndTime = !single`). Label "END TIME · optional" ("· optional" in `#b0b6c0`/600). Same pill row/behavior.

## f · Confirm button
Full-width lime (standard), margin-top 16. **Dynamic label:** single → "Use May 12"; range → "Use {N} days". When times on + single day, append " · {startTime}" ("Use May 12 · 09:00").

## Behavior summary (carry verbatim)
1. First tap = single-day (start = end); CTA "Use May 12".
2. Second tap extends to a range; tapping earlier than start flips them; a third tap starts over.
3. Times opt-in — end date alone suffices for most trips; times stay collapsed until asked for.
4. Scroll, don't paginate — months flow inline with snap; "3 weeks out" is a flick, not taps through a grid.
