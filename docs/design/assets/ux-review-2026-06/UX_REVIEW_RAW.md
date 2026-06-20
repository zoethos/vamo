# UX/UI Review Backlog

Source: Design review (Claude) / 2026-06-20 / mockups: `Vamo UX Improvements.dc.html` · screenshots in `docs/design/assets/`
Status: raw review, not yet triaged

Scope: full pass over every built view plus the spec/roadmap surfaces not yet implemented. Mockups built in the locked brand tokens; "Proposed" frames are interactive. Numbered references (①②③) below map to the lime markers in the mockup.

---

## High Priority

### H1 — Restore the 5-slot nav + context-aware goLime FAB
**Screens:** Main shell (global) · `assets/01-navigation-fab.png`
The shipped shell is a 4-slot bar (Trips · Activity · Expenses · Profile) with **no center FAB**, but the design brief and both approved brand boards specify a 5-slot nav with a center lime "+". Consequence: logging an expense — the core loop and highest-frequency action — has no global entry point (today ~3–4 taps via a horizontally-scrolling quick-action). It also explains why **goLime, the signature action color, is absent from live flows**, making the build read flatter than the boards.
- ① Add the docked lime FAB → expense logging drops to one tap from anywhere.
- ② Make it context-aware: "+expense" on the Expenses tab, "+trip" elsewhere. Retire the app-bar "+".
- ③ Brings the brand's action color into the core loop.

### H2 — Lighten Add Expense; make split editable; pin the CTA
**Screens:** Add Expense · `assets/02-add-expense.png`
Current form is a long single column of 9 fields. The spec itself flags `flow_abandoned` ("high abandonment = form too heavy"). Two concrete defects:
- The **split field is read-only** — it renders a label inside an `InputDecorator`; you cannot set equal/custom here even though the flow map promises it.
- The **Save CTA scrolls away** (left-aligned button at the bottom of a `ListView`).
Proposed: ① amount-first keypad (currency/receipt/place collapse to one tap each), ② inline Equal/Custom split with live per-person shares, ③ pinned lime CTA showing the running total, plus smart defaults (You paid · Equal · last category).

### H3 — Give Balances a summary "head"
**Screens:** Trip Balances / Balances tab · `assets/03-balances.png`
The built screen jumps straight into per-pair cards with no at-a-glance answer to "what's my number?". Proposed: ① the board's **net-balance donut hero** (owed vs. owe), ② a single lime **Settle up** CTA instead of a dark button per card; avatars + scannable rows replace the plain "Final balances" text list. The minimal-transaction settle engine is excellent and unchanged — this is the surface catching up to it.

### H4 — Build the Trip Map (journey replay) — the concept's moat
**Screens:** Trip Map *(roadmap, Wave 3, not built)* · `assets/04-trip-map.png`
The README calls the journey replay "the moat — no incumbent does this," yet it exists only as a "coming soon" fake door. Concept screen: ① every member's trail on one timeline, each a brand color and individually toggleable, with moments (photos / placed expenses) pinned to the route; ② a day scrubber driving replay (seed of the Wave-5 branching playback). Data hooks already exist (receipt EXIF lat/lng/time, per-expense places).

### H5 — Build Trip Wrapped (share the story) — the missing brand pillar
**Screens:** Trip Wrapped *(roadmap, Wave 3 / Tally, not built)* · `assets/05-trip-wrapped.png`
Brand promise = "split the costs, capture the journey, **share the story**." Wave 1 ships split + capture + a static snapshot, but the *story* is a "recap video — coming soon" door. Concept: ① a tap-to-advance recap story (totals, distance, photo/city counts, superlatives) built from data already captured, every frame share-ready with the permanent watermark; ② lime "Share your Wrapped" CTA. Highest-emotion share + strongest re-engagement hook at trip close.

---

## Medium Priority

### M1 — Resolve global vs. per-trip duplication
**Screens:** Activity tab vs. trip "Recent activity"; Expenses tab vs. per-trip expenses · `assets/06-review-notes.png`
"Where do I see what I owe?" currently has two answers. Make the global tabs unambiguous **aggregations that drill into** the per-trip views, not parallel destinations. The Expenses tab should be a cross-trip money home (balance header + per-trip rollups + period strip) and the home for the FAB's "+expense" trip-picker.

### M2 — Android platform hygiene (apply globally)
- Use **M3 `NavigationBar` + docked FAB**, not a hand-rolled `BottomAppBar`.
- **Edge-to-edge + predictive back** (Android 14+).
- **Dynamic-type-safe layouts** — retire the trip-hero's magic-number height math (see L1).
- **Credential Manager** sign-in (one-tap Google / passkeys).
- 48dp minimum targets; keep the **brand palette locked over Material You**.

### M3 — Harden the trip-hero layout
**Screens:** Trip Dashboard
`trip_dashboard_tab.dart` hand-computes hero height from magic constants (`_totalCardEstHeight`, `_cardHeroOverlapFraction = 0.33`) plus a post-frame measure-and-`setState`. Fragile under long trip names, large accessibility fonts, and RTL. Move to `CustomScrollView` + `SliverAppBar`.

### M4 — Profile / settings structure
**Screens:** Profile
One long scroll of section headers. Add a profile header (avatar + name + "Si va?"), group into M3 list sections with dividers, and consider a pinned save / snackbar over a bottom button. (Good existing discipline: primary action is never lime.)

### M5 — Warm up Auth / onboarding
**Screens:** Auth
Email OTP + Apple/Google + QR all work, but it's the first impression and reads like default Material. Warm toward the board (gradient / pattern) and render the **real wordmark asset** instead of the text "VAMO".

### M6 — Surface daily-value moments (Plan/Events)
**Screens:** Plan / Events *(Wave 2)*
RSVP chips (Going / Maybe / Declined) match the board. To earn *daily* opens, surface "next up" on the trip dashboard and the home Activity feed — not only inside the trip's Plan tab.

---

## Low Priority

### L1 — Quick-actions discoverability
Five fixed 76px tiles in a horizontal scroll push "Memories" (and "Balances" on group trips) off-screen. Use a 2-row wrap or a prioritized set.

### L2 — Photo-less trips look identical
Until trip photos / theme packs (Wave 2) exist, every new trip falls back to the same gradient. Consider destination-seeded gradient/pattern variation so trips feel distinct on day one.

### L3 — Settle-up state clarity
The marked → confirmed two-step can read ambiguously. Make "pending confirmation" a visibly distinct state (the boards show this; ensure the build matches). Keep it as quiet status, not a headline.

### L4 — Activity feed visual polish
Move off M2 `Card` + `ListTile` to M3; add trip thumbnails / member avatars to feed rows.

### L5 — Snapshot share theming
On-brand and the seed of the growth loop. Wire destination theme packs (Wave 2) so each trip's card differs; keep the permanent watermark; have Wrapped (H5) feed from the same composer.

---

## Open Questions

1. **Wave-1 stopgaps:** Do Trip Map (H4) and Trip Wrapped (H5) ship as the Wave-3 concepts shown, or do we also need polished "coming soon" fake-door versions to ship now and measure intent?
2. **FAB context rules:** Confirm the "+" mapping per tab — is "+expense" only on the Expenses tab, or also on a trip's expense view? What does "+" do on Profile?
3. **Global vs. per-trip (M1):** Should the Activity and Expenses tabs become pure aggregators, or retain any standalone create/entry affordances?
4. **Material You:** Confirm we fully override dynamic color with the locked brand palette (recommended), vs. tinting neutrals.
5. **Web share pages:** In/out for the near term? They close the invite loop for non-installers and lift the viral coefficient (see Screens below).
6. **Wrapped data availability:** Are distance and photo counts reliably available at close for the first Wrapped cut, or do we gate some frames?

---

## Screens / Flows Referenced

| # | Screen / Flow | Status | Mockup asset |
|---|---|---|---|
| 01 | Main shell / navigation + FAB | Built (4-slot) | `assets/01-navigation-fab.png` |
| 02 | Add Expense | Built | `assets/02-add-expense.png` |
| 03 | Balances (trip + tab) | Built | `assets/03-balances.png` |
| 04 | Trip Map / journey replay | Roadmap W3 — not built | `assets/04-trip-map.png` |
| 05 | Trip Wrapped / recap story | Roadmap W3 (Tally) — not built | `assets/05-trip-wrapped.png` |
| 06 | Auth / onboarding | Built | `assets/06-review-notes.png` |
| 06 | Expenses tab (money home) | Built | `assets/06-review-notes.png` |
| 06 | Activity feed | Built | `assets/06-review-notes.png` |
| 06 | Profile / settings | Built | `assets/06-review-notes.png` |
| 06 | Plan / Events | Wave 2 | `assets/06-review-notes.png` |
| 06 | Members & invite | Built | `assets/06-review-notes.png` |
| 06 | Snapshot share | Built | `assets/06-review-notes.png` |
| 06 | Close report | Wave 2 | `assets/06-review-notes.png` |
| 06 | Web share pages | Roadmap W2 — not built | `assets/06-review-notes.png` |
| — | Overview / index | — | `assets/00-overview.png` |

**Web share pages (roadmap W2):** view-before-install, domain-gated pages. Invite/snapshot links should open a themed web preview of the trip so invitees can see it without the app — closing the loop and lifting the viral coefficient.

---

## Implementation Notes

- **Interactive mockups:** `Vamo UX Improvements.dc.html` (editable) and `Vamo UX Improvements (standalone).html` (offline single file). Keypad, split toggle, map scrubber + trail toggles, and Wrapped tap-through are all live. Two tweaks: Annotations on/off; action-color swatch.
- **Keep as-is (validated):** minimal-transaction settle-up engine; "Vamo never moves money" deep-link model; sanitized-error policy; solo trips hiding Balances; the fake-door signal stack; contrast governance (goLime fill-only, coralText for small text).
- **Sequencing:** H1 and H2 are the highest-leverage and mostly front-end — do first. H3 follows naturally. H4/H5 are net-new surfaces gated to Wave 3; decide stopgap (Open Q1) before scheduling. M2/M3 are cross-cutting refactors — fold into the H1 nav work and the dashboard pass respectively.
- **Color rule:** lime (`#C6FF00`) is reserved for the single primary action per screen (FAB, Settle up, Save, Share Wrapped) — never decorative; small text uses coralText, not lime.
- **Metrics tie-in:** H2 targets `flow_abandoned`; H5 serves the Wave-2/3 "day-after-close retention ≥35%" goal; H1 + Members/invite + Web share pages drive the viral coefficient.
