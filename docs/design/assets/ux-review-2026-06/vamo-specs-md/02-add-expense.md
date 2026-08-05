# Implementation Prompt — Add expense (amount-first) · screen 02

**For:** Codex / Claude Code · **Stack:** Flutter + M3 · **Source:** `Vamo UX Improvements.dc.html` §02 (Proposed frame). Tokens & rules: `_DESIGN-TOKENS.md`. The "Current" 9-field form is the rejected build.

**The fix (review H2):** the current form is a long single column of 9 stacked fields; the split is **read-only**, and the Save CTA **scrolls away**. The spec itself flags `flow_abandoned` ("high abandonment = form too heavy"). Rebuild amount-first with an inline editable split and a pinned CTA.

---

## Layout (top → bottom, all on one non-scrolling screen)

App bar: `close` 22px + two-line title "New expense" 15px/700 over "Amalfi Coast" 11px `slate`.

**1 · Amount hero.** Centered. The live amount 42px/700 (letter-spacing -.02em), e.g. "€64.20". Below it a currency pill — inline-flex, 12px/600 `inkSoft`, bg `#E9ECF2`, padding 4px 10px, radius 999px: "EUR" + `expand_more` 16px.

**2 · Essentials chips** (centered row, gap 7px, padding 12px 16px 6px): two pill buttons (`surface`, 1px `#E9ECF2`, radius 999px, 12px/600):
- "**You paid**" — leading 16px coral avatar "Y" + label + `expand_more` `mute2`.
- "**Food**" — leading `restaurant` 15px orange + label + `expand_more`. (Currency / receipt / place collapse to one tap each — not stacked fields.)

**3 · Split control** (card: `surface`, 1px `#E9ECF2`, radius 14px, margin 8px 16px, padding 12px). Header row: "Split" 12px/700 + a 150px segmented toggle (`#E9ECF2` track, radius 9, padding 2): **Equal / Custom** buttons (selected `ink`+white, idle transparent `slate`).
- **Equal:** an avatar stack (four 24px circles, member colors, white initials Y/M/L/S, 2px white border, -7px overlap) + "Equally · **{per-person}** each" 12px.
- **Custom:** a list of member rows — 22px color avatar + name (flex) + an editable share chip ("{€share}" 13px/600 `ink`, bg `#F3F4F7`, radius 7, padding 4px 9px). Members: You (coral), Mara (jadeBright), Luca (plum), Sofia (orange). Per-person = round(total / 4).

**4 · Keypad** (fills remaining space, vertically centered): a 3-col grid `1 2 3 / 4 5 6 / 7 8 9 / . 0 ⌫`. Keys: transparent buttons, 23px/500 `ink`, padding 9px 0. Tapping a digit appends (amount tracked in cents: `cents*10 + d`); ⌫ removes last (`floor(cents/10)`); "." is a no-op.

**5 · Pinned CTA** (padding 8px 16px 14px): full-width lime button "Add expense · {amount}" (the "·" at 0.65 opacity) — the live total always reachable.

## Smart defaults
**You paid · Equal · last category** — so the common case is type-and-confirm.

## Why (carry verbatim)
- **Amount-first keypad** — the number you came to enter is the first thing you touch; currency/receipt/place collapse to one tap each.
- **Inline split editing** — switch Equal/Custom right here; today it's a read-only label even though the spec promises equal-or-custom.
- **Pinned lime CTA** with the live total — today Save is left-aligned at the bottom of a scrolling form.
- Directly targets the spec's **`flow_abandoned`** signal.
