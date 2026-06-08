# S44 — "Add to your trip" menu redesign + Change background

**Branch:** `feature/add-menu-change-bg` from `main` · **Est:** ~1.5–2 dev-days
Reworks the capture add menu (`capture_action_sheet.dart` → `CaptureChoiceSheet`)
and adds a user-set hero background. Consume S29 tokens; light + dark.

## Part A — add menu = magnified-center scrollable icon carousel
The old menu repeated "Add note / Add photo / Add video" as spaced rows running under
the system nav bar. Replace it with a compact, premium **carousel picker**:
1. **Icon carousel with a magnified center item.** A horizontally scrollable row of
   **circular icon options** — Photo · Video · Note · Background — where the
   **centered option is enlarged** and shows its **label** underneath; scrolling
   brings the next option to center; tap the centered item (or tap any item) to
   select. Icons only off-center; the centered one is labeled (covers the "drop the
   Add prefix" intent — no repeated "Add", the single centered label says what it is).
2. **Zero-dependency implementation:** a `PageView` with `viewportFraction ≈ 0.3` +
   an `AnimatedScale`/transform driven by page offset to magnify the centered item
   (or a `ListWheelScrollView` for a true wheel feel). No new package.
3. **Compact + safe-area:** the carousel is a short band; size the sheet to content
   and pad the bottom by `MediaQuery.viewPadding.bottom` so it never runs under the
   Android nav/gesture bar.
4. **Accessibility (important for an icon-first UI):** every option carries a semantic
   label (Photo/Video/Note/Background) for screen readers; the centered visible label
   keeps it clear for sighted users; options remain reachable without horizontal
   swipe gestures (tap-through fallback). Don't ship icon-only with no labels.
- Tradeoff note: for ~4 items a carousel is more motion than a static row — chosen
  for the premium feel + room to grow; keep it snappy (fast snap, no long animation).

## Part B — "Change background" (user-set hero badge image)
Add a **Background** tile to the menu that lets the user pick a picture to use as the
**trip hero/badge background**.
- **Stored separately from captures** — this is NOT a capture: do **not** write a
  `trip_photos` row and it must **never appear in the Memories/captures view**.
- **Data:** add a trip-level background reference — e.g. `trips.background_path`
  (migration, next free ordinal) or a `backgroundImage` key in the existing trip
  theme jsonb. Member-scoped RLS to set/read (mirror trip membership).
- **Storage:** upload the picked image to a private bucket (a `trip-backgrounds`
  bucket, or a distinct prefix in `captures` that the Memories query excludes).
- **Hero resolution chain:** **user background override → gradient fallback**
  (`SnapshotThemes`). (AI-generated destination art remains a separate, deferred
  feature — do not build it here; just leave the override slot so it can slot in
  later above the gradient.)
- **UI:** picking a new image replaces the current hero background immediately;
  offer replace/remove later (a "Change background" entry also in trip settings is
  optional). Scrim stays for title legibility over any image.
- Reuse `image_picker` (already a dep). Offline-tolerant like the capture path.

## Verification
- `melos run ci`; goldens for the new grid menu + a hero with a user background
  (light+dark+small+RTL).
- Background image renders in the hero; does **not** appear in Memories; survives
  reopen (persisted); scrim keeps the title ≥4.5:1.
- **On-device** (S25 Ultra): menu is a tight grid with noun labels, fits above the
  nav bar; Background tile sets the hero image; Note/Photo/Video still work.

## Reviewer checklist
- [ ] Menu is a grid of square tiles; labels are nouns (no "Add" prefix)
- [ ] Spacing tightened; content never under the system nav bar (bottom safe inset)
- [ ] Background tile sets the trip hero image
- [ ] Background stored separately; NOT a trip_photos row; absent from Memories
- [ ] Migration for the background reference (next free ordinal) + member RLS
- [ ] Hero resolves: user override → gradient; AI-gen slot left for later (not built)
- [ ] Goldens + a11y (scrim) + device pass

## Notes
- Part B is the **user-upload** half of the trip-picture idea (distinct from Postcard
  = capture backdrops, and from the deferred AI destination-art generation).
- Pairs with S43 (Memories surface) — Background must be excluded from that view.
