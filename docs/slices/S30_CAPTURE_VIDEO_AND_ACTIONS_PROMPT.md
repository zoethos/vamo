# S30 — Capture: add video + coherent action placement

**Branch:** `feature/capture-video` · **Est:** ~2–2.5 dev-days · **Depends:** S27 (UI polish I) merged; ideally consumes S29 tokens if landed
**Why:** two problems in the Capture tab. (1) **Action placement is incoherent** —
every other trip tab (Expenses/Plan/Members) puts its primary action in the shared
**bottom FAB**, but the FAB is disabled on Capture and the tab grows its own inline
**Add note / Add photo** Row at the *top* of the list. Buttons must live in a
consistent place. (2) **Video capture is missing** — captures are notes + photos
only; add video as a first-class capture type.
**Out of scope:** the Postcard backdrop render (separate, see `docs/POSTCARD_SPEC.md`);
audio notes (W4); device-location tagging (W3 TripMap); video editing/trimming.

## 0. Current state (read before coding)
- `packages/feature_split/lib/src/trips/trip_home_screen.dart:282` — the trip-home
  `FloatingActionButton.extended` is **nulled on Capture** (`onCaptureTab`) and
  dispatches per tab: Plan → `_planTabKey.currentState?.openAddPlanItem()`,
  Members → `_membersTabKey.currentState?.openInviteFlow()`, Expenses → push
  add-expense. **This is the pattern to match.**
- `packages/feature_split/lib/src/capture/capture_tab.dart:84-113` — the inline
  Add-note/Add-photo `Row` at the top of the `ListView`. **This is what to remove.**
- Captures: tables `trip_notes`, `trip_photos` (`0003`), private `captures` bucket
  + member-scoped Storage RLS (`0005`/`0009`), realtime publication (`0004`),
  lifecycle delete-block on closed trips (`0015`). Drift offline-first + sync;
  `capture_repository.dart` has `addNote` / `addPhoto` (offline-tolerant: stays
  local on Drift if bucket missing/offline, uploads when able).

## 1. Part A — coherent action placement (FAB → capture sheet)
- **Remove** the inline action Row at the top of `capture_tab.dart`. Keep the
  helper text + empty state.
- **Enable the trip-home FAB on Capture.** Add a `_captureTabKey`
  (`GlobalKey<...>`) like `_planTabKey`/`_membersTabKey`; expose
  `openAddCapture()` on the Capture tab state.
- Because Capture has **three** actions (note/photo/video), the FAB opens a
  **modal bottom sheet** (`useSafeArea: true`, consistent with the plan-item
  sheet at `plan_tab.dart:223`) listing: **Add note**, **Add photo**, **Add
  video** — icon + label rows. (A speed-dial / expanding FAB is a deliberate dep;
  do NOT add one — the sheet is zero-dep and matches Members opening a flow.)
- FAB label/icon on Capture: generic **Add** (`Icons.add`) — one icon language
  with the other tabs; don't reintroduce per-screen button styling.
- Loading state (photo/video upload in progress) shows on the in-sheet row or a
  snackbar — **not** as a relocated inline button.
- A11y labels on the FAB and each sheet row. RTL-correct. ARB strings (no new
  hardcoded copy — wire through `app_en.arb` + the labels classes used by Capture).

## 2. Part B — add video capture
Mirror the photo path end to end; **reuse the `captures` bucket and its existing
RLS** (generic on `bucket_id='captures'` + uid/tripId folder — videos need no new
bucket or policy).

- **Pick:** `image_picker` is already a dependency → `pickVideo(source: gallery)`
  (and camera where available). **Cap with `maxDuration`** (proposed 60s) to bound
  file size. No new pick dependency.
- **Model:** add a `TripVideoView` (mirror `TripPhotoView`) in `capture_models.dart`.
- **Repository:** add `addVideo(...)` in `capture_repository.dart` mirroring
  `addPhoto` — Drift-first, upload to `captures`, insert row, offline-tolerant.
- **Migration (next free ordinal):** `trip_videos` mirroring `trip_photos`
  (`id, trip_id, storage_path, caption, captured_at, created_by, created_at`) +
  index + RLS (`is_trip_member`) + realtime publication add + lifecycle
  delete-block-on-closed policy (match `0015` for notes/photos).
  **Forward-compat (Postcard, governance rule 1):** also add `captured_lat`,
  `captured_lng` (EXIF-derived, **no device-location permission**) so the
  irreplaceable capture-time geo is stored now. Consider backfilling the same
  columns onto `trip_photos`/`trip_notes` in this migration.
  **Numbering:** `0026`=S25, `0027`=S23 are on `main`; S22 holds `0028`. Claim the
  **next free ordinal at implementation time** (likely `0029`); if order shifts,
  renumber — migrations are monotonic.
- **UI cell:** a `CaptureVideoCell` (mirror `CapturePhotoCell`) showing a frame/
  placeholder with a play affordance + duration; tap → full-screen playback.
- **Playback dependency (deliberate):** in-app playback needs `video_player`
  (and optionally `chewie` for controls). Register in `docs/DEPENDENCIES.md`
  (lock-in rating, why). Thumbnail generation (`video_thumbnail`) is **optional /
  deferred** — until then use a generic video tile with a play icon. If a
  zero-dep MVP is preferred, open the video via the OS instead and defer in-app
  playback — call this out in the PR.
- **Size/sync caution:** videos are heavy. Keep the offline-tolerant insert, but
  flag upload behavior (immediate vs queue / wifi-only) as a decision in the PR;
  don't silently block the UI on a large upload.
- **Analytics:** `add_capture_video` event mirroring `add_capture_photo`; no PII,
  no amounts, no storage paths.

## 3. Verification
- `melos run ci` green.
- **Goldens:** Capture tab with the FAB + sheet, and the video cell, at
  small-screen + dark + RTL. Assert **no** inline top action Row remains.
- Widget test: FAB present on Capture; opens sheet with three actions; each routes
  correctly (note → add-note screen, photo → picker, video → picker).
- Repo/smoke: `addVideo` inserts `trip_videos` + uploads to `captures`; offline
  path stays local on Drift; closed-trip delete blocked (lifecycle parity).
- **On-device pass (device-verify rule — CI can't see native pickers/playback):**
  add a video on the S25 Ultra → appears in the grid → plays back; add note/photo
  still work from the new sheet; no overflow; FAB sits where Plan/Members FAB sits.

## 4. Reviewer checklist
- [ ] Inline top action Row removed; Capture uses the shared trip-home FAB
- [ ] FAB opens a bottom sheet with Add note / Add photo / Add video (icon+label, a11y, RTL)
- [ ] One icon language with the other tabs; no per-screen button styling
- [ ] `trip_videos` mirrors `trip_photos` (table + index + RLS + realtime + closed-delete block)
- [ ] Reuses `captures` bucket + existing Storage RLS (no new bucket/policy)
- [ ] `captured_lat/lng/at` stored at capture time (Postcard forward-compat; EXIF only, no device-location permission)
- [ ] `pickVideo` with `maxDuration`; offline-tolerant insert; large-upload behavior decided in PR
- [ ] Playback dep (`video_player`) registered in DEPENDENCIES.md, or zero-dep OS-open MVP called out
- [ ] `add_capture_video` analytics: no PII / paths / amounts
- [ ] Migration at next free ordinal; monotonic (coordinate with S22 `0028`)
- [ ] Goldens (small + dark + RTL) + device pass green

## Notes
- This makes video a Postcard-consuming capture type (`docs/POSTCARD_SPEC.md`);
  the geo columns added here are exactly what Postcard later reads.
- Pairs with S29 (tokens) — the FAB/sheet should consume the system, not
  reintroduce hardcoded colors/spacing.
