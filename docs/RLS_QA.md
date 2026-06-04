# Wave 1 — RLS QA checklist

Run before TestFlight / Play internal. Use the Supabase dashboard **RLS tester** (or SQL as `authenticated` vs a second test user).

## Setup

1. Two test accounts: **Owner** (creates trip) and **Outsider** (not a member).
2. `supabase db push` — all migrations applied, including storage policies `0005`.

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

## Capture storage (`trip-photos` bucket)

| Check | Expected |
|-------|----------|
| Member reads `userId/tripId/file` for their trip | Allowed (signed URL or direct read per policy) |
| Outsider reads same path | **Denied** |
| Upload path matches `auth.uid()/tripId/...` | Required for INSERT policy |

Confirm `0005` policies run as the `storage` role and `public.is_trip_member(...)` is executable for that role.

## Settlements & invites

| Check | Expected |
|-------|----------|
| Member marks settlement on trip | Allowed |
| Outsider reads `settlements` for trip | **Denied** |
| Valid invite token via `join_trip` | Adds `trip_members` row, fires `invite_accepted` client-side |

## Suggestions (`0006_suggestions.sql`)

| Check | Expected |
|-------|----------|
| User A inserts a suggestion | Allowed |
| User A reads own suggestions | Allowed |
| User B reads User A's suggestions | **Denied** |
| Client updates/deletes a suggestion | **Denied** (no policy) |

## Sign-off

- [ ] All rows above verified on **cloud** project (not only local).
- [ ] No `service_role` key embedded in the Flutter app.
- [ ] `snapshots` / `trip-photos` buckets are **private** (no public list).
