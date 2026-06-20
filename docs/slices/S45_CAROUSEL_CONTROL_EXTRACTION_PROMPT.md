# S45 — Extract the capture-carousel into a reusable control

**Goal:** make the carousel a **neat, dependency-free, reusable control** — usable in any
view with no code duplication. Separate the *generic control* from the *capture-specific
wiring*.
**Where it goes:** the generic control lives in **`app_core`** (the shared design layer —
every feature package already depends on it), **not** a new melos package yet. Per the
S31/S32 rule, promote to `packages/vamo_carousel` only when a 2nd distinct surface uses it
or it needs independent versioning. A shared widget in `app_core` already gives "reusable
everywhere, zero duplication" without package-sprawl overhead.

## The split
Today everything lives in `feature_split/.../capture/capture_action_sheet.dart`, mixing
the reusable control with capture choices. Cut it cleanly:

### A. Generic control → `app_core/lib/src/design/vamo_carousel.dart` (no app deps)
Move the presentation + interaction primitives (currently `_CaptureFlyoutOverlay`,
`_CaptureCarouselMetrics`, `_CaptureChoiceOrb`, `_CaptureFocusedLabel`, the
`ListWheelScrollView.useDelegate` wheel, the OverlayEntry/`CompositedTransformFollower`
anchor + dismiss). It must know **nothing** about capture, trips, `image_picker`,
Supabase, or Riverpod — only Flutter + app_core tokens (`VamoCircleIcon`, type/space/motion).

**Public API:**
```dart
class VamoCarouselItem {
  const VamoCarouselItem({
    required this.icon,
    required this.label,        // shown only when centered (Material wheel convention)
    required this.onSelected,
    this.color,                 // optional accent; defaults to token
    String? semanticLabel,      // a11y; defaults to label
  });
}

/// Anchored vertical elliptical wheel flyout: magnified centered item, smaller
/// semi-solid neighbors, white-ring orbs (VamoCircleIcon), centered label, dismiss
/// on outside-tap or selection.
Future<void> showVamoCarousel({
  required BuildContext context,
  required LayerLink anchor,            // anchors the flyout to a button (e.g. the camera +)
  required List<VamoCarouselItem> items,
  VamoCarouselAxis axis = VamoCarouselAxis.vertical,
  // styling pulled from tokens; magnification, pill opacity, etc. have sane defaults
});
```
Carries the look we tuned: translucent pill, solid magnified center, smaller semi-solid
neighbors, `VamoCircleIcon` white rings, label-only-when-centered (FittedBox so it can't
clip), respects `MediaQuery.textScaler`, full a11y semantics.

### B. Capture-specific wiring → stays in `feature_split`
`capture_action_sheet.dart` becomes a thin builder: it constructs the capture
`VamoCarouselItem`s (Photo→pickImage, Video→pickVideo, Note→add-note, Background→
setTripBackground) and calls `showVamoCarousel(...)`. **Zero carousel-rendering code
remains here** — only the item list + the action callbacks. The `_CaptureChoice` enum and
the handlers (`_setBackground`, `_addPhoto`, …) stay in the app.

## Guardrails (so it stays clean)
- The S32 **import-guard** must forbid `vamo_carousel.dart` from importing `feature_split`,
  `image_picker`, `supabase`, `drift`, or `flutter_riverpod` — it's a pure UI primitive.
- Style only from app_core tokens + `VamoCircleIcon` (no hardcoded colors) so it inherits
  light/dark + the circular-icon coherence rule automatically.

## Tests
- **Generic** (`app_core`): widget/golden tests for the carousel in isolation —
  centered-label-only, magnified center, white rings, dismiss, a11y semantics,
  large-text-scale (no clip). Independent of capture.
- **Capture wrapper** (`feature_split`): keep the existing behavior tests (Background/Photo/
  Video/Note select + the error-path test) — now exercising the thin wrapper.

## Reuse / promotion criteria
- Now: one consumer (capture) → keep in `app_core`. Done.
- Promote to `packages/vamo_carousel` only when (a) a 2nd distinct surface uses it, **or**
  (b) it needs independent release. Record that trigger in `docs/architecture/ARCHITECTURE_BOUNDARIES.md`.

## Verification
- `melos run ci` (incl. the import-guard) green.
- A throwaway second usage (a test harness mounting `showVamoCarousel` with dummy items)
  proves it works with **no** capture/app dependencies — that's the "reusable, no
  duplication" proof.
- On-device: the capture carousel behaves exactly as before (it's a refactor — no UX change).

## Notes
- Pure refactor + extraction; no behavior change for the user.
- Pairs with the circular-icon coherence (VamoCircleIcon) and S31/S32 boundaries work.
