# Provider credits and attribution

## Goal

Show required provider credits in Vamo surfaces that use provider-backed data,
starting with OpenRouteService road-distance feasibility. This is compliance and
trust polish, not a new feature surface.

## Scope

- Add a small provider-credit component that can render one or more credits:
  - OpenRouteService: road distances / routing.
  - OpenStreetMap contributors: map tiles/data where already required by map
    surfaces.
  - Future providers: Foursquare place info, weather, AI providers when a
    provider explicitly requires attribution.
- Surface the credit only where provider-backed output is visible:
  - AI route draft review / feasibility warnings when road distances were used.
  - Trip Map already shows map attribution; keep it consistent with the shared
    copy/component if practical.
  - Website/About can reuse the same copy later, but do not block the app slice.
- Keep the credit quiet: small `labelSmall`, muted color, no lime, no CTA weight.
- Add links only where the platform/surface supports safe external opening.

## Out of scope

- No provider switcher/dashboard work.
- No extra provider calls.
- No usage metering changes.
- No blocking gate if attribution metadata is unavailable.
- No legal-page rewrite; website/About credits are a later content pass.

## Implementation notes

- Treat `provider_config.requires_attribution` as the source of truth for
  provider-backed outputs that come from the control plane.
- For `draft-trip-route`, expose enough response metadata for the client to know
  whether road distance was used, for example `distance_provider:
  openrouteservice` or `feasibility_distance_source: road`.
- Render the credit near the AI route feasibility/review details, not as a
  modal or banner.
- Suggested copy:
  - `Road distances by OpenRouteService`
  - `Map data OpenStreetMap contributors`
- If the route-distance layer falls back to straight-line haversine, do not show
  the ORS credit for that specific draft.

## Architecture decision

**Inline/shared UI component.** The rule is presentation-only and depends on
provider metadata already owned by the backend control plane. Keep the widget
small in the app package; promote later only if three or more surfaces need
custom provider-credit composition.

## Tests / guardrails

- Dart widget test: route review shows ORS credit when route-distance metadata
  says road/ORS was used.
- Dart widget test: no ORS credit when feasibility used only straight-line
  fallback.
- Edge test: `draft-trip-route` response marks road-distance usage without
  leaking provider keys or raw request details.
- No live ORS/OpenAI call in tests or CI.
- `melos run ci` green; Deno function tests remain green.

## Done

- Provider credit visible in the AI route review/feasibility area when ORS road
  distances are present.
- Copy is subdued and does not compete with the primary action.
- Website/About credit follow-up is documented but not required for this slice.
