# Implementation Prompt — Expenses list refactor · screen 15

**For:** Codex / Claude Code · **Stack:** Flutter + M3 · **Source of truth:** `Vamo Expenses Refactor.dc.html` ("Proposed" frame is the spec; "Current" frame is the rejected build). Tokens & rules: `_DESIGN-TOKENS.md`. Match pixel-for-pixel.

This is the **per-trip Expenses list** — the list of costs — **separate from Balances** (who owes who). The old build was never refactored: merchant titles wrap then repeat in the meta, "Propose a cost" floats as teal text, cards are heavy, there's no total/balance context or day grouping. Bring it in line with Activity & Plan.

---

## Layout

App bar (padding 8px 16px): `arrow_back` 23px + two-line title "Expenses" 17px/800 over "Amalfi Coast" 11px `slate` + trailing `search` 22px `inkSoft`.

**Summary strip (spend-led).** Margin 2px 16px 10px. A dark `ink` card, radius 14px, padding 12px 14px, flex row gap 12px:
- TOTAL SPENT — label 10px/700 `mute2` (.04em) over value 20px/800 white ("€49.20").
- A 1px×30px divider `rgba(255,255,255,.16)`.
- YOUR SHARE — label over 14px/700 white ("€24.60").
- Right: a quiet **Balances** link — 11px/700 `#FF8A7A` + `chevron_right` 15px. (Connects the two surfaces; doesn't duplicate them.)

**Filter chips** (gap 7px, padding 0 16px 8px): All · Unsettled · Mine. Same chip style as Activity (`ink`/white selected, `segBg`/`slate` idle).

**List** (scrolls, padding 0 6px), grouped by day. Day header row (space-between, padding 6px 12px 4px): day label left 10px/700 `mute` (.06em, "TODAY · JUN 5") + day subtotal right 10px/600 `#b0b6c0`.
- **Expense row** (gap 11px, align center, padding 9px 12px, radius 13px, tappable):
  - Leading 38×38 radius-10 **receipt thumbnail** (gradient placeholder) with a small 18px round **category badge** bottom-right (`1.5px #FAFAFB` border, bg = category color, white 11px MSO icon).
  - Body two single lines: title 13.5px/700 (short merchant name, ellipsis) + meta 11px `mute` reading **payer · place · date** (ellipsis) — e.g. "Tiziano paid · Termini · Jun 5".
  - Trailing right-aligned: amount 14px/800 over your-share 10.5px `mute` ("€48.00" / "you €24").
- Demo: Borri Books (plum `menu_book`, €48 / you €24), Sfizio (orange `restaurant`, €1.20 / you €0.60), Ferry tickets (orange `directions_boat`, €32 / owed €16). Categories use the existing category catalog colors/icons.

**Empty state** (per filter): centered `receipt_long` 38px `borderDash` + hint 13px/600 `slate` ("No unsettled costs." / "Nothing you paid for yet.").

**Context FAB — "Propose expense".** Bottom-right, lifted (`right:16px; bottom:18px`): a labelled lime pill — `add` 21px `ink` + "Propose expense" 14px/700 `ink`, bg lime, radius 16px, padding 13px 16px, shadow `0 8px 20px rgba(198,255,0,.5)`. **This is the screen's single lime control.**

---

## Why (carry verbatim)
- **Expenses = the list of costs (this screen). Balances = who owes who (the net-donut screen).** Both are per-trip sections; this one was never refactored, which is why it looked like Expenses had "become" Balances. Now visibly different and cross-linked.
- **Clean title hierarchy.** Short merchant title on one line (the long legal name moves to a tap-through detail); meta stops repeating it and reads *payer · place · date*. `maxLines:1 + ellipsis`.
- **Spend-led summary.** Total spent + your share on top, with a quiet link across to Balances — connected, not duplicated.
- **M3 rows, day-grouped.** Small receipt thumbnail + category badge, amount + your-share right-aligned, day subtotal — same row language as Activity & Plan. Filters: All · Unsettled · Mine.
- **"Propose expense" becomes the lime action** — the consent-model wording stays, but it's the one lime control (a labelled FAB) instead of floating teal text.
- Global **Expenses** tab = the cross-trip money home that aggregates these per-trip lists; tapping a trip lands here.
