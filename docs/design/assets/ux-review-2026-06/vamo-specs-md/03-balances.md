# Implementation Prompt — Balances (net hero + settle) · screen 03

**For:** Codex / Claude Code · **Stack:** Flutter + M3 · **Source:** `Vamo UX Improvements.dc.html` §03 (Proposed frame). Tokens & rules: `_DESIGN-TOKENS.md`. The "Current" stack-of-cards frame is the rejected build.

**The fix (review H3):** the built screen jumps straight into per-pair cards with no at-a-glance answer to "what's my number?", and puts a dark button on every card. Give Balances the board's **net-balance donut hero** + a single lime **Settle up**. The minimal-transaction settle engine underneath is excellent and unchanged — this is the surface catching up to it.

---

## Layout

App bar: `arrow_back` 22px + "Balances" 16px/700.

**1 · Net-balance donut hero.** Centered, padding 10px 0 4px. A 132×132 ring drawn with `conic-gradient(#00C2A8 0 74%, #FF5B4D 74% 100%)` (jadeBright = owed-to-you arc, coral = you-owe arc; sweep proportional to the split). A 14px inset hole filled `appBg` holds, centered: "Net balance" 10px `slate` / value 23px/700 ("€386.20") / "You're owed" 10px/700 jade.
- **Legend row** below (centered, gap 16px): jadeBright dot + "Owed to you **€586.20**"; coral dot + "You owe **€200**".

**2 · Settle-up list.** Label `SETTLE UP` 12px/700 `slate`. Then scannable avatar rows (each: 32px color-circle initial + "{name} owes you" / "You owe {name}" 13px with the verb in `slate` + right-aligned amount 13px/700). Rows divided by 1px `#F0F1F4`.
- Demo: Marco (jadeBright "M") owes you €120.50; Lina (orange "L") owes you €85.30; You owe Alex (coral "A") €64.20 — **the "you owe" amount in `coralText #D7402F`.**

**3 · Pinned CTA.** Full-width lime **"Settle up"** (standard) — the one lime control. (No per-card dark button.)

Keep the marked → confirmed settle states, but as **quiet status, not the headline** (see backlog L3).

## Why (carry verbatim)
- **Net-balance hero.** The board's signature donut answers "what's my number?" in one glance.
- **One lime "Settle up" CTA** instead of a per-card dark button — settle is the action color's home turf.
- Avatars + scannable rows replace the plain "Final balances" text list.
- The settle-up engine (minimal transactions) is excellent — this is purely the surface catching up to it.
