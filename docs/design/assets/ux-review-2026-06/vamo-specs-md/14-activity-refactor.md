# Implementation Prompt — Activity refactor · screen 14

**For:** Codex / Claude Code · **Stack:** Flutter + M3 · **Source of truth:** `Vamo Activity Refactor.dc.html` ("Proposed" frame is the spec; "Current" frame is the rejected build). Tokens & rules: `_DESIGN-TOKENS.md`. Match pixel-for-pixel.

Activity is a **passive, read-only, cross-trip audit log** — distinct from Notifications, and it gains **no actions of its own**. The refactor narrows its job and raises fidelity: compact M3 rows with trip + actor identity where **the icon carries the verb** (no "added/settled up" text), every row **drills into its trip surface**, richer sources, and filters. **No lime anywhere — a history has no primary action.**

---

## Layout

App bar (padding 8px 18px): two-line title "Activity" 19px/800 over "Across all your trips" 11px `slate`; trailing `notifications` 23px `inkSoft` (links to the separate Notifications surface).

**Filter chips** (horizontal, gap 7px, padding 4px 18px 10px): All · Money · Plan · Members · Media. Chip 12px/700, padding 7px 14px, radius 999px. Selected: `ink` bg + white. Unselected: `segBg` bg + `slate`.

**Feed** (scrolls, padding 0 6px), grouped under day labels (10px/700 `mute`, .06em, padding 8px 12px 4px): **Today · Yesterday · Earlier**.

**Row** (~48px; display flex, gap 12px, align center, padding 11px 12px, radius 13px, tappable):
1. **Leading identity** — a 34×34 radius-9 **trip-thumbnail** (gradient per trip) with a small **18px round actor/type badge** bottom-right (`1.5px #FAFAFB` border, bg = type accent, white 11px MSO icon). The badge icon **is the verb**.
2. **Body** (two single lines): line 1 = **actor** (700) + object (400 `#3a3f4b`) — e.g. "**Marco** → you", "**Sofia** Villa Rufolo", "**Luca** joined"; line 2 = "{trip} · {time}" 10.5px `mute2`. Both `maxLines:1 + ellipsis`. **No verb word.**
3. **Trailing** — an optional quiet amount (12.5px/700; `jade` when you're owed/positive `+€120.50`, `coralText #D7402F` when you owe "owe €32"), then always a `chevron_right` 17px `#c8ccd4`.

**Empty state** (per filter): centered `history` 40px `borderDash`, "Nothing here yet" 14px/600 `slate`, "No {money/plan/member/media} updates across your trips." 12px.

**Bottom nav** — the **5-slot bar with docked context FAB** (see tokens rule 4): Trips · Activity(active) · [lime ＋] · Expenses · Profile. 56px bar, 1px `#E9ECF2` top, `surface`. The ＋ belongs to the app, **not** to Activity.

Demo feed rows: Marco→you (money, `payments`, jade +€120.50, Amalfi, 2h) · Sofia · Villa Rufolo (plan, coral `place`, 4h) · Luca joined (members, plum `person_add`, Bali, 5h) · You · Dinner (money, orange `restaurant`, owe €32 coralText, 18:30) · Mara · 6 photos (media, sky `photo_camera`, 16:05) · You · Sunset hike (plan, jadeBright `event_available`) · Priya joined (members, `how_to_reg`, Lisbon, Mon) · Lisbon Getaway closing soon (lifecycle, `flag`, slate, Mon).

---

## What changed & why (carry verbatim)
- **Every row drills through.** Expense→trip expenses, Settlement→balances, RSVP/plan→plan item, Member joined→members. The chevron makes it a deep link, not an action.
- **The icon says the verb.** The badge encodes the action, so the verb word is dropped — rows keep only **actor + object**. One tight line, no wrapping.
- **Tighter type.** Primary 13px (actor 700 / object 400), meta 10.5px, 34px trip badge → ~48px rows (vs ~70px). Flutter: bodyMedium@13 / labelSmall / labelMedium for amount.
- **Richer sources.** Adds member-joined, Visit/plan-item added, photo/note, invite accepted, lifecycle (closing/closed) — not just `kind==activity`. Filters: All · Money · Plan · Members · Media.
- **Color fixed.** Lime removed from settlement/RSVP rows — a passive log has no primary action. Accents come from existing type/category tokens; amounts quiet (coral when you owe).
- **No FAB, no inbox.** The context-fab in the nav belongs to the app, not Activity. Accept/Object/Settle stay in their real flows (and Notifications).
- Name stays "Activity"; revisit "Updates" only if it stays sparse after drill-through + sources land.
