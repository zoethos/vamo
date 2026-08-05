# Implementation Prompt — Trip Wrapped (recap story) · screen 05

**For:** Codex / Claude Code · **Stack:** Flutter + M3 · **Source:** `Vamo UX Improvements.dc.html` §05 (concept frame). Tokens & rules: `_DESIGN-TOKENS.md`. **Status: roadmap Wave 3 (Tally) — not yet built.**

**The missing brand pillar (review H5):** brand promise = "split the costs, capture the journey, **share the story**." Wave 1 ships split + capture + a static snapshot, but the *story* is a "recap video — coming soon" door. Build a tap-to-advance recap story — highest-emotion share + strongest re-engagement hook at trip close.

---

## Format — a full-screen, tap-to-advance story (like IG/Spotify Wrapped)
Full-bleed screen. **Tap anywhere advances** to the next slide (wraps around). At top: a row of **progress segments** (one per slide, gap 5px, 3px tall, radius 2) — filled lime `#C6FF00` up to and including the current slide, `rgba(255,255,255,.28)` ahead. Every frame is screenshot-ready and carries the permanent watermark.

## The four slides (each a full-bleed gradient, white text, content vertically centered, 26px side padding)

**Slide 0 — Cover.** Gradient `linear-gradient(160deg,#FF5B4D,#FFA766 38%,#6A2D6F)`. Eyebrow "VAMO · 2026 WRAPPED" 12px/700 (.18em). Title "Amalfi Coast" 40px/800 (-.02em). "May 12 – 20 · 4 friends" 14px. "Tap to begin ›" hint.

**Slide 1 — Spend.** Gradient `linear-gradient(160deg,#2a1840,#0C0E16)`. "Together you spent" 15px → "**€1,245**" 54px/800 in **lime** → "across 32 expenses in 5 cities" 14px. A frosted callout (`rgba(255,255,255,.1)`, radius 12): "Your share · **€311.40** — and you're **owed €386** back" (the owed amount in `#00E0C2`).

**Slide 2 — Distance & counts.** Gradient `linear-gradient(160deg,#00C2A8,#07595C 55%,#0C0E16)`. "You went the distance" → "1,280 **km**" (50px/800 + 24px unit). Then a 3-stat row: 8 days · 37 photos · 5 cities (each number 28px/800 over a 12px label).

**Slide 3 — Superlatives.** Gradient `linear-gradient(160deg,#6A2D6F,#0C0E16)`. Title "Trip superlatives" 18px/800. Three award rows (30px color avatar + small label + name): "Biggest spender · You · €498" (coral Y), "Most photos · Mara · 19" (jadeBright M), "First one up, every day · Luca" (orange L). Below, the lime **"Share your Wrapped"** CTA (standard pill).

## Why (carry verbatim)
- **Story format** (tap to advance) — familiar, screenshot-friendly; every frame a share moment carrying the permanent watermark.
- **Built from data you already have** — totals, photo counts, members, places. The Tally/Wrapped surface the roadmap names, dressed for sharing.
- Serves the Wave-2/3 retention metric: "day-after-close retention ≥35%." Feed it from the same composer as Snapshot share.
