# S47 — Multi-source profile picture (Horizon A)

**Why.** Avatars are the social/sharing surface that drives growth, but a forced manual
upload at onboarding gets skipped → generic silhouettes everywhere. Give every user a
recognizable avatar with near-zero effort by defaulting to the avatar already attached to
their OAuth identity, with manual upload and an initials fallback. Privacy-by-default.

**Scope = P0 only.** Crop + provider re-pull/refresh (P1) and per-trip override (P2) are out.

## A. Storage — `avatars` bucket + RLS (migration, timestamped name)
- Create a **private** `avatars` bucket. Objects keyed `{userId}/profile.{ext}` (one per
  user; re-upload upserts).
- RLS on `storage.objects` for bucket `avatars` — **INSERT + SELECT + UPDATE** (upload,
  upsert, read), mirroring the captures-policy pattern in `0005`/`0015`:
  - **INSERT / UPDATE**: `(storage.foldername(name))[1] = auth.uid()::text` — a user may
    only write their own `{uid}/…` path.
  - **SELECT**: `auth.role() = 'authenticated'`. **Conscious tier decision:** avatars are
    treated as the **same privacy tier as `display_name`**, which `profiles_read` already
    exposes to any authenticated user (`0001`). State this in a SQL comment in the migration;
    if that tier tightens, this policy tightens with it.
  - No DELETE policy in P0 (overwrite handles replace); a delete-on-unlink path is noted, not built.
- Add to `StoragePaths` (`packages/app_core/lib/src/storage/storage_paths.dart`):
  `avatarsBucket = 'avatars'` + `userAvatar({userId, ext})`.

## B. Capture the OAuth avatar — client-side (NO DB trigger)
- A Postgres trigger can't fetch an external image. Do the copy **in the profile-completion
  flow** (or a thin Edge Function if server-authoritative is preferred).
- Read `picture` / `avatar_url` from the Supabase session user metadata **as source data
  only** → download the bytes → upload to `avatars/{uid}/profile.{ext}` → store the
  **storage path** in `profiles.avatar_url`.
- **Never store the provider URL** (expires; leaks presence on every render). **Never use
  `raw_user_meta_data` for any authorization decision** — it is user-writable; content hint only.

## C. Profile model + repository
- Extend `UserProfile` (`packages/app_core/lib/src/profile/profile_models.dart`) with
  `avatarUrl` (the storage path); read it in `fromRow`; include `avatar_url` in
  `fetchCurrent`'s SELECT (`profile_repository.dart`).
- Add `updateAvatar(path)`; clearing to initials = set null.

## D. Rendering + completion UX
- `VamoAvatar` (`packages/app_core/lib/src/design/vamo_avatar.dart`): add an **initials**
  fallback. Render order: **stored photo path → initials (brand teal) → person silhouette**.
- Profile-completion screen (`packages/feature_split/lib/src/profile/profile_screen.dart`):
  preview the OAuth avatar (if any) with **[Use this]**, **[Upload]** (`image_picker` →
  `avatars`), **[Use initials]**.

## E. Tests
- `tool/rls_smoke.dart`: own `{uid}/profile.*` INSERT/UPDATE/SELECT pass; writing another
  user's path is blocked; an authenticated user **can** SELECT others' avatars — **assert
  this deliberately**, so a future tier-tightening breaks the test on purpose.
- Widget: initials fallback when `avatarUrl` is null; completion screen shows the three
  options; "Use initials" clears the avatar.

## F. Guardrails / done =
- New users via Google/Microsoft get a one-tap real avatar; manual upload + initials both
  work; **nothing hot-links a provider URL**; `raw_user_meta_data` is never an authz input.
- Avatar = display-name privacy tier, stated in the migration comment. `melos run ci` green;
  `rls_smoke` green (now N+ checks).
- **Open (legal, not P0):** retention of the provider-sourced copy after a user unlinks that
  login — keep storage/schema able to support a delete-on-unlink path; defer the policy.

## Notes
- Wires the already-present `profiles.avatar_url` (`0001`, currently unused) and
  `VamoAvatar.photoUrl` (already supported) — this slice *extends*, it doesn't invent surface.
- P1 (crop/refresh) and P2 (per-trip override) reuse this storage + model; don't pre-build them.
