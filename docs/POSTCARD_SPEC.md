# Postcard — `vamo_postcard` package spec

**Status:** spec · 2026-06-07 · package not yet extracted
**Decision:** founder-named "Postcard" (2026-06-07). See `docs/AI_IDEATION_GOVERNANCE.md` ledger.
**Relates:** `places` keystone (`supabase/migrations/0011_places.sql`), Capture view
(`packages/feature_split/lib/src/capture/*`), S30 (add-video), TripMap (W3), TripReel (W4).

## 1. What it is

A small, reusable Flutter package that turns a **resolved place** (name, address,
lat/lng) into a **visual backdrop**, so every captured artifact — receipt, note,
photo, video — can read like a *postcard from that place*. The expensive half
(knowing *where*) is already solved by the `places` table; Postcard is mostly a
**resolve-and-render** layer on top.

Two reasons it's a package and not receipt code:
1. **Cross-feature reuse** — the same backdrop logic serves receipts, capture
   notes (text; audio later), capture photos, and capture videos. Today it lives
   welded inside the Capture view; this extracts it behind one seam.
2. **One cost-bearing seam** — the only parts that touch the network/cost (venue
   photo lookup, static-map tiles) sit behind a single provider interface that is
   cacheable, swappable, and governed like every other external provider.

## 2. The two jobs

### a. Resolve — `PostcardBackdrop` from a `Place`
A strict, **always-succeeds** fallback chain (never throws, never blank):

1. **Web venue photo** — keyed on place name + address (and coords as a
   disambiguator). Provider behind an interface (e.g. a Places-photo API). Cached.
2. **Static map image** — a map render at the place's lat/lng. Provider behind an
   interface (static-map / tile API). Cached.
3. **Styled fallback card** — brand-token gradient/pattern (no network) when both
   above are unavailable or the place has no usable signal.

The chain degrades gracefully and is **offline-tolerant**: a cached asset or the
styled fallback always renders; a failed lookup is a soft miss, never an error
surfaced to the user (mirror the existing capture pipeline's "stays local / shows
placeholder" posture).

### b. Render — `Postcard(place:, child:)`
One widget that paints the resolved backdrop behind arbitrary capture content
(`child`), with a legibility scrim so foreground text/controls stay readable
(the same contrast guard that keeps `goLime`-on-light bugs out — never render
unreadable foreground over a busy photo).

## 3. API surface (proposed)

```dart
// Input — already available from the `places` resolution today.
class Place {
  final String label;        // venue / company name
  final String? address;
  final double? lat;
  final double? lng;
}

// Resolved, ready-to-paint backdrop.
sealed class PostcardBackdrop {}
class VenuePhotoBackdrop  extends PostcardBackdrop { /* image provider + attribution */ }
class StaticMapBackdrop   extends PostcardBackdrop { /* image provider */ }
class FallbackBackdrop    extends PostcardBackdrop { /* brand tokens, no network */ }

abstract class PostcardResolver {
  Future<PostcardBackdrop> resolve(Place place);   // runs the fallback chain
}

class Postcard extends StatelessWidget {
  const Postcard({required this.place, required this.child, this.height, super.key});
  final Place place;
  final Widget child;
}
```

Provider wiring (venue-photo, static-map) is injected, not hardcoded — so the
package ships with a default + can be swapped/mocked in tests without platform
channels.

## 4. Provider & resilience posture

The venue-photo and static-map lookups are **external providers** and MUST follow
`docs/design/PROVIDER_RESILIENCE.md` and the control-plane conventions:
- **Cache to avoid the call** — resolved backdrops keyed by place identity;
  cache hit short-circuits the network (same principle as the theme cache and FX
  rates). This is also the cost control.
- Respect Retry-After / backoff; transient-vs-quota distinction; fail **loud in
  telemetry, soft in UI** (fall through to the next chain step, never a 500-style
  surface).
- Register the chosen static-map + venue-photo providers in
  `docs/architecture/DEPENDENCIES.md` with lock-in rating, keys, and cost ceiling **before**
  first use (deliberate dependency — not a casual add).

## 5. Data needs (forward-compatible, cheap now)

Capture tables (`trip_photos`, `trip_notes`, and the new `trip_videos`) currently
**lack** lat/lng (only `expenses` carries `captured_lat/lng/at` from `0008`). For
Postcard to enrich captures later, the **capture-time geo must be stored when the
artifact is created** — that is irreplaceable data (governance rule 1). Recommend
adding `captured_lat`, `captured_lng`, `captured_at` (and optionally `place_id`
referencing `places`) to the capture tables. EXIF/address-derived only — **no
device-location permission** for the W2-eligible core.

## 6. Consumers

| Surface | Content (`child`) | Notes |
|---|---|---|
| Expense receipt | receipt card / thumbnail | place already resolved via `places` + `expenses.place_id` |
| Capture note | note card | text now; audio note later (W4) |
| Capture photo | photo cell / detail | |
| Capture video | video cell / player frame | ships with S30 add-video |
| Share snapshot / OG | snapshot card | optional later — Postcard as a share frame |

## 7. Scope & wave split (founder decides placement)

- **W2-eligible core:** resolve + render from a place we **already have**
  (EXIF/address-derived), no new permission. Rides `places`. Slice-sized.
- **W3 (TripMap):** the **live device-location** flavor (tagging a capture with
  the device's current position) belongs with TripMap's opt-in location flow.
- **W4 (TripReel):** audio/video notes *pinned to a map* and stitched into recap.

Per "respect settled decisions": this spec **proposes**; the founder picks which
wave the core rides. Nothing is pulled forward without an explicit OK.

## 8. Privacy

- No new permission for the W2 core (address/EXIF only).
- Backdrop assets are presentation-layer; no PII, amounts, or member identity in
  any provider request or analytics.
- Venue-photo attribution honored per provider terms.

## 9. Verification (when built)

- Golden tests for each backdrop state (venue photo / static map / fallback) at
  small-screen + dark + RTL; legibility scrim verified.
- Resolver unit tests: fallback chain order, cache hit short-circuits the network,
  soft-miss never throws.
- Provider mocked — no live network in tests.
- A11y: foreground contrast over each backdrop type passes (no unreadable text).

## 10. Open decisions (resolve at slice time)

1. Static-map provider + venue-photo provider (cost, keys, attribution).
2. Cache store + TTL + invalidation key (place identity hash).
3. Add place columns to capture tables now (S30) vs at the Postcard slice.
4. Which wave the W2-eligible core rides.
