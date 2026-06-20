# H-P0 — Weather preview on upcoming trips (Horizon H, selective)

**Why.** Travelers check the forecast elsewhere before a trip. Folding "what's it going to be like
when we land" into the upcoming list + featured card deepens the emotional pull of the trip card and
earns pre-trip opens — without sending the user out of the app.

**Scope = P0 (ships value, no art pipeline):** when a trip is **pre-start and starts within 7 days**,
show a small **condition badge (bucket icon + temp)** for the **trip's start date** on the featured
trip card and in the upcoming list. Forecast is fetched server-side and normalized to a provider-
agnostic condition bucket. No coordinates / provider failure ⇒ **no badge, no error** (silent).

**Explicitly P1 (fast-follow, not here):** the weather-image **blend** on the featured card (rain /
snow / thunderstorm overlays composited on the hero). Real design work — gated behind P0 proving the
data flows; must stay on-brand and keep card text legible.

## Provider decision (settled)
- **P0 / beta provider: Open-Meteo, behind an edge gateway.** Free, no key, ≥7 forecast days, and it
  ships **both** a geocoding API (`geocoding-api.open-meteo.com`) and the forecast API — one provider
  for destination→coords→forecast.
- **Commercial caveat:** Open-Meteo's free tier is non-commercial — treat as *prototype/beta only*.
  Swap to a licensed provider (WeatherAPI Starter/Pro, OpenWeather One Call, …) **before public
  scale**. The gateway + condition-bucket abstraction make that a **server-only** change.

## Condition bucket abstraction (from day one)
The UI only ever sees a bucket, never a provider code:
`sunny | cloudy | rain | thunderstorm | snow | fog | unknown`
Server maps Open-Meteo WMO `weathercode` → bucket:
`0–1 → sunny · 2–3 → cloudy · 45,48 → fog · 51–67,80–82 → rain · 71–77,85,86 → snow · 95–99 → thunderstorm · else → unknown`.

## A. Edge function `weather-forecast` (Deno) — server does everything
- **Input:** `trip_id` (query or body). **Not** client destination text — prevents forging arbitrary
  places to burn the (eventually metered) weather quota.
- **Auth:** require the caller's JWT; read the trip via a **user-scoped client** so RLS enforces
  membership (non-members get `trip_not_found`). Read `destination` + `start_date` server-side.
- **Flow:** cache lookup → (miss/stale) Open-Meteo geocode `destination` → forecast for `start_date`
  → map WMO → bucket → upsert cache → return `{ available, bucket, temp_high, temp_low, date }`.
- **Graceful:** missing destination/date, geocode miss, or upstream failure → `{ available: false,
  reason }` with HTTP 200 (the client just hides the badge).
- Mirror `fx-rates` conventions (CORS `OPTIONS`, `json()` helper). Deploy:
  `supabase functions deploy weather-forecast`. No new client-side API key — key (if any, post-swap)
  stays in function secrets.

## B. Cache (`weather_forecast_cache` table)
- Key `(destination_key, forecast_date)`; columns `bucket, temp_high, temp_low, fetched_at`.
- **~6h TTL** refetch (a forecast a week out doesn't move minute-to-minute; this protects the quota).
- **RLS on, granted to service_role only** — clients never read it directly; they call the function.
  Written/read by the function via the service-role client.

## C. Client (badge only — P0)
- `weather_repository` calls the edge function with `trip_id`; returns a `WeatherPreview?`
  (`bucket`, `tempHigh`, `tempLow`) or null.
- Trigger gate: show only when `resolveTripPhase(...) == preStart` **and** start date is within 7 days
  (reuse the existing pre-start/date logic in `trip_lifecycle.dart`).
- Surfaces: **featured trip card** + **upcoming list** rows — a compact `WeatherBadge` (bucket icon +
  temp). Bucket→icon map lives client-side (Material weather icons); strings are l10n-ready.
- Cache the preview locally per trip (short TTL) so list scroll doesn't refetch.

## D. Tests
- **Edge:** `condition_bucket` WMO→bucket mapping table (sunny/cloudy/rain/thunderstorm/snow/fog/unknown
  boundaries) — pure, unit-tested.
- **Dart:** `WeatherPreview` parse (incl. `available:false` → null); the 7-day pre-start trigger
  predicate; `WeatherBadge` renders the right icon per bucket.
- **rls_smoke:** an authenticated member can call `weather-forecast` for their trip; a non-member /
  outsider gets `trip_not_found`; `weather_forecast_cache` is not directly readable by `authenticated`.

## E. Guardrails / done =
- Provider-agnostic: UI depends only on the bucket enum; provider swap = gateway-only.
- Silent degrade everywhere (no destination, no coords, upstream down → no badge, never an error toast).
- Migration via `supabase migration new`; apply to **staging** (`sfwziwcuyctxvidivnsh`, **not** prod —
  CLI is linked to prod) + `rls_smoke` green; `melos run ci` green; goldens on Linux if the card
  surface changes; watch the `AppColors` ratchet.
- **No client-side weather API key.** Open-Meteo needs none; any future key lives in function secrets.

## Notes
- **Branch base:** `feat/weather-preview` off `main`.
- Builds on existing pieces: `geocodeAddress` is *not* used (server geocodes via Open-Meteo for
  consistency); `resolveTripPhase`/date logic reused for the trigger; `fx-rates` is the edge-fn
  template; S46 notifications are **out of P0** (forecast-change push is a later H increment).
- P1 (image blend) and forecast-change notifications are separate follow-ups — keep P0 to the badge.
