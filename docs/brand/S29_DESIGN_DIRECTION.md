# S29 Design Direction

Founder-approved visual direction for `docs/slices/S29_DESIGN_SYSTEM_FOUNDATION_PROMPT.md`.
Use this as the taste input for tokens and component theming.

## Canonical References

- Light app direction: `docs/brand/Vamo-Light-Theme.png`
- Dark app direction: `docs/brand/Vamo-Dark-Plum.png`

Any `TooClumsy` variants are rejected explorations, not canonical references.

## Logo

Keep the existing Vamo mark assets as canonical:

- `docs/brand/primary_mark.png`
- `docs/brand/journey_mark.png`
- `docs/brand/mark_ink.png`
- `docs/brand/mark_white.png`
- matching app assets under `app/assets/brand/`

Do not replace the logo with the alternate road/sun mark shown in generated
reference boards. The founder preference is the current heart/road-shaped Vamo
mark over the V-with-sun alternate.

## Light Theme

Primary direction: `Vamo-Light-Theme`.

Intent:

- Warm, travel-native, social, optimistic.
- "Travel together. Share everything." should feel like the product promise.
- Use cream/warm-white surfaces, ink/deep-teal text, sunrise/coral/mango travel
  warmth, and mint/sky action accents.
- Keep operational screens calm. The travel warmth belongs most strongly in
  trip hero, snapshot, invite/share, empty states, and small accent moments.

Avoid:

- Beige-heavy generic travel UI.
- Over-decorating every utility screen with photos/textures.
- Replacing financial clarity with lifestyle imagery.

## Dark Theme

Primary direction: `Vamo-Dark-Plum`.

Intent:

- Cool, premium, confident, "night mode that feels intentional."
- Plum, ink, jade teal, coral, and go-lime action accents can carry more drama
  in dark mode than in light mode.
- Excellent fit for dark theme, trip hero/snapshot, balances, and premium-feeling
  focused work surfaces.

Avoid:

- Making dark mode neon everywhere.
- Using go-lime as body text, icon foreground, or borders. Go-lime remains CTA /
  FAB / high-salience action only, with ink foreground when used on light/action
  fills.

## Token Decisions

- Palette source: light foundation from `Vamo-Light-Theme`; dark foundation from
  `Vamo-Dark-Plum`; reconcile into the existing `AppColors` / `AppTheme` instead
  of creating a second palette.
- Type choice: use the platform/system font stack for the app for now. Goldens
  keep deterministic `NotoSans` with existing Arabic/Hebrew/Chinese/Devanagari
  fallbacks.
- Type scale: compact mobile-first scale. Use hierarchy through weight, line
  height, and spacing rather than oversized editorial headings.
- Radius/elevation: utility controls and repeated cards stay restrained
  (about 8-12px radius, subtle elevation); hero/snapshot surfaces can use
  16px and richer visual treatment.
- Signature surface: trip hero / trip snapshot first. Share page can inherit
  later.

## Circular Icons (S42)

Every circular icon badge or button uses one shared treatment via
`VamoCircleIcon` in app_core:

- Per-use **fill color** (avatar, surface, solid white for capture, etc.).
- **2px white border** on every circle so icons read as one family on photos
  and colored surfaces.
- **Soft shadow** on hero/snapshot/colored backgrounds; may be omitted on flat
  utility surfaces (e.g. activity feed on a card) when shadow adds noise.

Applies to: member avatars, add tile, hero capture camera, activity row icons,
snapshot member bubbles, My Trips notification bell, and any future
`CircleAvatar` / circular `IconButton` over imagery.

## Cursor Scope Guard

S29 should implement the token/component substrate. It should not redesign every
screen, globally repaint every `AppColors` usage, add font/media dependencies,
or replace the logo. Deeper screen-by-screen polish belongs to the next mobile
UI pass.
