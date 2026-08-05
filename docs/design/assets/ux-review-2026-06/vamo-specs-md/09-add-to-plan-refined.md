# Implementation Prompt — Add to Plan, refined (Visit) · screen 09

**For:** Codex / Claude Code · **Stack:** Flutter + M3 · **Source of truth:** `Vamo Add-to-Plan Refined.dc.html` (the "Optimized" frame is the spec; the "Current" frame is the rejected build, shown only for contrast). Tokens & rules: `_DESIGN-TOKENS.md`. Match pixel-for-pixel.

This is the **Add-to-Plan sheet for a Visit**. The current build has three defects to fix: (1) a nested double-box search field with an oversized icon column, (2) clashing colors (plum + teal + coral + lime fighting), (3) an empty Notes block outranking the field that matters.

---

## Layout (the Optimized frame)

App bar: leading `close` 24px + a two-line title — "Add to plan" 17px/800 over "Amalfi Coast · Day 3" 12px `slate`.
Body padding 18px (horizontal), 8px top.

**1 · Type picker.** A 3-column grid (`repeat(3,1fr)`), gap 9px, margin-bottom 18px. Six tiles (the six types — see tokens). Each tile: column layout, center, gap 6px, padding 13px 0, radius 14px, **1.5px** border.
- **Selected:** border = type accent, bg = accent + `12` alpha. Icon tile inside (34×34, radius 9) = accent bg + white icon; label = accent text.
- **Unselected:** border `border`, bg `surface`. Icon tile bg `#F3F4F7` + `slate` icon; label `inkSoft`.
- Icon 20px MSO; label 11px/700. Default selected: **Visit** (coral).

**2 · Place search (single clean field).** Label row, baseline: "Place" 13px/700 `ink` left; the active type name right in that type's accent ("Visit" in coral).
- **One pill** (no nesting, no icon column): 1.5px **coral** border, radius 14px, padding 13px 14px, `surface`, `box-shadow:0 0 0 3px #FF5B4D1A`. Contents: small inline `search` 20px coral + query text 15px filling the width (ellipsis) + a trailing `cancel` (×) 19px `mute2` that clears.

**3 · Suggestion dropdown** (under the field, margin-top 8px): `surface`, 1px `hairline` border, radius 14px, shadow `0 6px 18px rgba(12,14,22,.06)`. Each row padding 11px 12px, gap 11px: a 34×34 radius-9 **coral-tint** tile with `place` 19px coral; name 13.5px/600 + meta 11px `slate` (both ellipsis); selected row tinted `#FF5B4D0D` with trailing `check_circle` 20px coral. Rows 1–2 divided by 1px `#F0F1F4`.
- Demo suggestions: Abbazia di Montecassino (Abbey · Cassino · 1.5 km), Montecassino War Cemetery (Memorial · Cassino), Rocca Janula (Castle · Cassino · hilltop). Picking one sets query text to its name.

**4 · Address (optional, compact).** Margin-top 12px. Standard field: leading `location_on` 20px `mute2`, text 14px `mute2` ("Add address", or the resolved address once a place is picked), trailing "optional" 11px/600 `mute2`. *(Picking a place auto-fills this.)*

**5 · Notes (collapsed).** A one-line affordance (padding 13px 4px 4px, cursor pointer): `add` 20px `plum` + "Add a note" 14px/600 `plum`. **Not** a big empty box.

Helper line below: 12px `mute2` "Suggestions follow what you type."

Footer CTA (lime, standard): label is **"Add Visit"** once a place is picked, else "Save".

---

## What changed & why (carry verbatim)
- **One clean search field.** The nested purple+teal double-box → a single pill: small inline search icon, full-width text, clear (×). No icon column eating the typing area.
- **One accent per context.** Visit = coral — selected tile, search icon, focus border, suggestion highlight all coral. Purple and teal borders gone. **Lime reserved for Save only.**
- **Re-ordered by importance.** Place → live suggestions → Address (optional) → Notes. The empty Notes block no longer outranks the field that matters — it collapses to a one-line "Add a note".
- **Live POI resolution + tighter copy.** Suggestions appear inline as you type — tap to pick (no address typing). One short helper line replaces three; nothing truncates.
- A picked place sets the title, fills the address, drops a pin on the Trip Map, and names the CTA "Add Visit".

> The other five types (Flight/Train/Transfer/Lodging/Other) share this shell but show type-specific fields — see `11-add-to-plan-types.md`.
