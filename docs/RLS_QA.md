# Wave 1 — RLS QA checklist

Run before TestFlight / Play internal.

## Automated smoke test (recommended)

Against your **cloud** Supabase project (never commit credentials):

```bash
dart pub get
# Set: SUPABASE_URL, SUPABASE_ANON_KEY,
#      RLS_USER_A_EMAIL/PASSWORD, RLS_USER_B_EMAIL/PASSWORD, RLS_USER_C_EMAIL/PASSWORD
# (three password-auth test users — create once in Supabase Auth dashboard)
dart run tool/rls_smoke.dart
```

The script creates a throwaway trip, verifies member vs outsider access (including **captures** bucket receipt paths with four segments), suggestions isolation, `trip_members` self-insert denial (`0007`), and **S16 role cases** (`0012`/`0013`: member cannot edit trip, co-admin can, co-admin cannot grant roles), then cleans up storage. Exit code `0` = all checks PASS.

Use this as the primary storage + RLS gate; manual steps below remain as an appendix.

## Setup

1. Two test accounts: **Owner** (creates trip) and **Outsider** (not a member). The smoke script uses three users (A/B/C).
2. `supabase db push` — all migrations applied, including storage policies `0005`, security hardening `0007`, roles `0012`/`0013`, push devices `0014`.

## Trip privacy

| Check | Expected |
|-------|----------|
| Owner selects own `trips` row | Allowed |
| Outsider selects that `trip_id` | **Denied** (empty / RLS error) |
| Outsider selects `expenses` for that trip | **Denied** |
| Outsider selects `trip_members` for that trip | **Denied** |
| Outsider calls `join_trip` with invalid token | Error, no row inserted |

## Member access

| Check | Expected |
|-------|----------|
| Member (after invite join) reads trip expenses | Allowed |
| Member inserts expense on trip | Allowed |
| Member updates own profile | Allowed |
| Member updates another user's profile | **Denied** |

## Capture storage (`captures` bucket)

Path convention (enforced in app via `StoragePaths` — `foldername[1]` = owner, `[2]` = trip):

| Path | Example |
|------|---------|
| Capture photo | `{userId}/{tripId}/{photoId}.jpg` |
| Expense receipt | `{userId}/{tripId}/receipts/{expenseId}.jpg` |

| Check | Expected |
|-------|----------|
| Member reads object for their trip (signed URL) | Allowed |
| Outsider reads same path | **Denied** |
| Upload path `[1]` = `auth.uid()` and `[2]` is member trip | Required for INSERT policy |

Confirm `0005` policies run as the `storage` role and `public.is_trip_member(...)` is executable for that role. **`dart run tool/rls_smoke.dart`** covers member read + outsider deny for receipt paths.

## Settlements & invites

| Check | Expected |
|-------|----------|
| Member marks settlement on trip | Allowed |
| Outsider reads `settlements` for trip | **Denied** |
| Valid invite token via `join_trip` | Adds `trip_members` row, fires `invite_accepted` client-side |
| Direct `trip_members` insert by outsider | **Denied** (`0007` drops `members_insert`) |

## Suggestions (`0006_suggestions.sql`)

| Check | Expected |
|-------|----------|
| User A inserts a suggestion | Allowed |
| User A reads own suggestions | Allowed |
| User B reads User A's suggestions | **Denied** |
| Client updates/deletes a suggestion | **Denied** (no policy) |

## Sign-off

- [ ] `dart run tool/rls_smoke.dart` PASS on cloud project
- [ ] All manual rows above spot-checked if needed
- [ ] No `service_role` key embedded in the Flutter app
- [ ] `captures` bucket is **private** (no public list)

## Appendix — manual storage steps

If you cannot run the script, verify in the Supabase dashboard **RLS tester** (or SQL as `authenticated` vs a second test user):

1. Member: `createSignedUrl` on `{uid}/{tripId}/receipts/{id}.png` → fetch succeeds.
2. Outsider: same path → **403** / error.
3. Outsider: `select` on `trips`, `expenses`, `trip_balances` for that `trip_id` → zero rows.
