# Implementation Prompt — Place Info Card + swipe-to-open · screen 13

**For:** Codex / Claude Code · **Stack:** Flutter + M3 · **Source of truth:** `Vamo Place Info Card.dc.html` (interaction frame + card) and `PlaceInfoCard.dc.html` (the reusable card itself). Tokens & rules: `_DESIGN-TOKENS.md`. Match pixel-for-pixel.

One reusable **PlaceInfoCard** opened from any POI row via a right-to-left **swipe → teal Info action** (long-press is the a11y fallback). The same sheet appears from the suggestion list, Visit timeline rows, and Map markers. **POI accent is teal `#07595C`; lime stays CTA-only** (only the card's "Add to plan" button is lime).

---

## Part A — Swipe interaction (suggestion row)

Inside the Add-to-Plan (Visit) context: a coral search field ("Ravello") and a `SUGGESTED PLACES` label paired with a hint "swipe for info" (10.5px/600 teal, leading `swipe_left` 14px).

**The slidable row:** a `position:relative; overflow:hidden` container, radius 12px, with a **teal `#07595C` action panel revealed behind it on the right** (width 84px, column-centered: `info` 22px white + "Info" 11px/700 white). The foreground row (`surface`, 1px `#F0F1F4` border, radius 12px, padding 11px 12px) translates left as you drag.
- Leading 38×38 radius-10 coral-tint tile + `place` 20px coral; name 14px/700 + meta 11.5px `slate`; trailing glyph = `drag_indicator` when closed, `chevron_left` when open (19px coral).
- **Drag mechanics:** clamp translateX to `[-84, 0]`. On release, snap open if dragged past 50% (`-42`), else closed. Open transition `transform .22s cubic-bezier(.2,.8,.2,1)`; none while dragging. Tapping the row toggles open/closed (but a drag that moved >4px is not treated as a tap). Tapping the revealed **Info** panel opens the card.
- Flutter: `flutter_slidable` `endActionPane` with `extentRatio 0.28`, DrawerMotion; generalize via `onInfo`/`infoLabel` on `VamoSlidableRow` so any row can gain info-on-swipe. **Long-press opens the same card** (discoverability + a11y).

Static rows below (no swipe) for contrast: Duomo di Ravello, Terrace of Infinity — same row chrome without the action panel.

Opening the card = a bottom sheet at 88% height (scrim `rgba(12,14,22,.45)`, top radius 22px) hosting `PlaceInfoCard`.

---

## Part B — PlaceInfoCard (the reusable sheet)

A single component, fed by a neutral `PlaceInfo` value object. Two presentations via a `hero` flag: **sheet** (`hero:false` — shows grabber + close button) and **full hero** (`hero:true` — no grabber/close). `bg appBg`.

**Hero photo** (height 168px, gradient placeholder `linear-gradient(135deg,#6fae54,#2f6b4f 58%,#1d4636)` for the real photo) with a top scrim `linear-gradient(to top,rgba(12,14,22,.5),transparent 55%)`:
- Top-left **photo-count pill**: bg `rgba(255,255,255,.92)`, padding 5px 10px, radius 999px, 11px/700 teal, leading `photo_camera` 14px ("6 photos").
- Top-right (sheet mode) **close button**: 30×30 round `rgba(12,14,22,.5)` + `close` 19px white.
- Bottom-left: name 21px/800 white (text-shadow) + "{category} · {price}" 12px white/.95.

**Body** (padding 4px 18px):
- **Rating + hours row:** `star` 17px `#F5A623` + rating 13px/700 + "· {count}" 400 `mute2`; a 3px dot; then a tappable **"Open now"** group — 7px jade dot + "Open now" 13px/700 jade + "· closes {time}" 400 `slate` + a chevron (`expand_more`/`expand_less`). Tapping expands a **week-hours panel** (`#F3F6F6` bg, radius 11px): seven rows "{day} … {hrs}", today's row in `ink`/700, others `slate`.
- **About** paragraph 13px/1.55 `inkSoft` with a trailing teal "more" link (700).
- **Detail rows** (each: top 1px `#F0F1F4`, padding 11px 0, gap 12px): a 34×34 radius-9 **teal-tint `#E1EEEE`** tile with teal 19px icon, then an uppercase 10.5px/700 `mute2` label over a 13.5px/600 value. Rows: ADDRESS (`place`), PHONE (`call`), WEBSITE (`language`, value in teal).

**Footer** (top 1px `#EEF0F4`, padding 12px 16px 16px, gap 10px): a 52px-wide secondary **directions** button (1.5px teal border, `surface`, `directions` 20px teal) + the lime **"Add to plan"** CTA (standard) filling the rest.

`PlaceInfo` fields → card: `photoUrl, name, category, rating, priceLevel, hours, address, phone, website, about`.

---

## Design notes (carry verbatim)
- **Swipe action is teal, not lime.** Lime stays CTA-only — here only "Add to plan" is lime.
- **Long-press fallback** opens the same card (discoverability + a11y).
- **Same quota, more fields.** `poi-discovery` adds `description, tel, website, rating, price, hours, photos` to the existing Foursquare call → `PoiSummary` → `PlaceInfo.fromPoi`. One `showPlaceInfoCard(context, info)` entry point reused from suggestion list, timeline rows, and map markers.
- **Phase 2/3 (noted, not built):** snapshot into `VisitPlaceMetadata` on save so saved Visits carry their card; later a lazy `placeinfo` enrichment (Wikipedia/Wikivoyage/OpenTripMap, optional LLM note) fills a richer "about".
