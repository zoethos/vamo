# S29 — Design system foundation ("finest UI" substrate) · BACKLOG

**Status:** backlog / not scheduled · **Est:** ~3–4 dev-days (+ Figma exploration)
**Sequencing:** ideally lands **before deep polish (S28)** and feeds S23/S25/S27 —
but parked for later by founder decision. This is the *substrate*, not a screen pass.
**Why:** the app reads "slice-assembled." Fine, appealing UI comes from a
**disciplined system + restraint + a few signature moments**, not more graphics
per screen. The `goLime`-as-`primary` drift (one token → whole class of
lime-on-light bugs) proved the leverage is at the token layer.

## Principle
**Subtractive, not additive.** Premium feel = calm screens, strong hierarchy,
one primary action, generous whitespace, limited palette — plus 1–2 genuinely
beautiful signature surfaces. Don't gold-plate every screen.

## 1. Tokens (single source of truth)
Define once as Flutter `ThemeExtension`s; nothing hardcoded downstream:
- **Color** — brand palette + semantic roles (primary=deepPlum/ink, goLime =
  filled-CTA/FAB-on-ink only; never foreground on light). Light + **dark** mode.
- **Type scale** — the biggest premium lever: font pairing, a real modular scale,
  consistent weights/line-height/tracking, semantic text styles (display/title/
  body/label). Get this right first.
- **Spacing** — 4/8pt grid; one spacing scale.
- **Radius / elevation** — consistent corner radii; a single light model for shadows.
- **Motion** — standard durations + curves (enter/exit/emphasized); use everywhere.

## 2. Core component set (small, crafted, reused)
Buttons (primary/secondary/text), inputs/fields, chips/segmented, cards, sheets,
app bar, list rows, empty/loading/error states, snackbars. Each: all states
(default/hover/pressed/disabled/focus), a11y labels, RTL-correct. Built on
Material 3 ("expressive") customized with the tokens — don't fight the platform.

## 3. Motion & micro-interactions (restrained)
Fast, physical, purposeful: implicit animations, Hero shared-element transitions
(trip card → trip), tasteful state transitions. No decorative motion. 60/120fps,
no jank.

## 4. Signature surfaces (spend the graphics budget unevenly)
Pick **1–2** to make genuinely beautiful; keep utility screens clean:
- **Trip hero / themed snapshot** (consumes S23 theme tokens).
- **Share page hero + OG image** (S25).
- Eventually the **journey replay** (the real wow feature).
Custom illustration / cohesive icon set / high-quality imagery live here. If
animated illustration is wanted, evaluate **rive/lottie** as a *deliberate*
dependency (register + cost), not a casual add.

## 5. Process (taste in, then execute)
- **Figma first** (Figma plugin): explore visually, build the token + component
  library in Figma, then translate to Flutter. Design-then-build, not build-then-tweak.
- Reference a high bar (Mobbin / Apple HIG / M3) for the patterns being polished.
- Use the `design` skills iteratively: `design-system` (tokens), `design-critique`
  (per screen), `accessibility-review` (contrast — keeps lime-on-light from returning).
- **The scarce input is visual direction/taste** — a strong reference or a
  designer sets the bar; the system + tooling execute it consistently.

## 6. Verification
- **Golden tests** for the component library + key screens (small-screen + standard).
- **RTL + dark-mode** goldens.
- `accessibility-review` (WCAG contrast) clean — no lime-on-light, ever.
- On-device pass (visual quality only proves on a real screen).

## Notes
- This underpins **S27 (polish I, done)** and **S28 (polish II)** — they're
  framed as fixes; this makes them build on a real system instead of patching.
- Reconcile with existing `app_theme.dart` + `AppColors` + Slice-12 theme packs —
  formalize/extend, don't duplicate.
- Monetizable themes (B2B+branding) ride on top of this token system later.
