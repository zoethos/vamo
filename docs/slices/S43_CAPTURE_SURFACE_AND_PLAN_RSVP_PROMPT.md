# S43 — Capture surface restore + Plan RSVP compaction

**Branch:** `feature/capture-surface-and-rsvp` from `main` · **Est:** ~1.5–2 dev-days
Two post-redesign cleanups. Consume S29 tokens; light + dark.

## Part A — captures home + final capture IA (FINAL decision)
Captures save (`addPhoto`/`addNote` → `trip_photos`/`trip_notes`) but the gallery was
unreachable, then a wrong default made the camera open Memories and buried the add
menu. **Final, decided IA:**
- **Memories = a quick-action tile.** Add **Memories** to the dashboard
  `quick-action-grid` (Expenses · Plans · Balances · Members · **Memories**),
  navigating to `TripMemoriesScreen` (the gallery — reuse/restyle `CaptureTab`'s
  grid+notes to S29 tokens). Memories is reached from the **grid**, not the camera.
- **Quick-action grid becomes horizontally scrollable.** With 5 tiles (and room to
  grow), make `_QuickActionsRow` a horizontally-scrollable row of fixed-width tiles
  so it never overflows and new tiles just extend the scroll. (Wrapping 2-row grid is
  an acceptable alternative.)
- **Camera button = the add-menu.** `trip_home_screen.dart` `onCapture` →
  `showCaptureActionSheet` (NOT push Memories). The sheet is the **S44 grid flyout**:
  **+ Photo · + Video · + Note · Change background**.
- Confirm `addPhoto` actually persisted the test image (trip_photos row + storage).
- **Not in scope:** setting a captured photo as the trip *background* — that's the
  S44 `change-background-tile` (separate, never shown in Memories) / the deferred AI
  art. Don't conflate.

## Part B — Plan RSVP: one control + per-card state icon
Each event card renders the full `PlanEventRsvpChips` (Going/Maybe/Declined) — repeated
per event, space-heavy (`plan_event_tile.dart:127`).
- **Per-card: a compact RSVP state indicator** — a small colored pill/icon showing the
  current user's status: Going (teal check), Maybe (amber), Declined (coral ×), or an
  outlined "RSVP" when unset. No always-visible 3-button control.
- **One shared RSVP control:** tapping the state pill opens a single reusable picker
  (small bottom sheet or popup menu) with the three options; selecting updates status.
- Keep the **going/maybe/declined counts** as a tiny summary (avatars + count), but
  drop the per-card segmented button.
- Reuse the existing RSVP data/providers (`event_rsvp_models`, `PlanEventRsvpChips`
  logic) — this is a presentation change, not a data change.

## Verification
- `melos run ci`; goldens for the Memories screen + the compact event card
  (light+dark+small+RTL); RSVP states (going/maybe/declined/unset) render distinctly.
- **On-device** (S25 Ultra): add a photo → it appears in Memories; event cards show a
  single state icon, tapping opens the RSVP picker and updates; much tighter Plan list.

## Reviewer checklist
- [ ] Captures viewable again (Memories screen, reachable from dashboard); add path kept
- [ ] addPhoto persistence verified (not silently failing)
- [ ] Event cards: compact RSVP state icon + one shared picker; no per-card segmented button
- [ ] RSVP counts kept; data/providers unchanged
- [ ] Trip-background-from-photo explicitly out of scope (not conflated)
- [ ] Goldens + a11y + device pass

## Notes
- Part A closes a regression from S37; Part B is the founder's space-saving redesign.
