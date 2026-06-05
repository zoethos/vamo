# S18 — TripBoard plan items (W2·R4) · implementation prompt

**Branch:** `feature/tripboard` · **Est:** ~2 dev-days · **Depends:** S17 merged
**Spec:** `Vamo_Wave2_Spec.md` R4 · seed `docs/WAVE2_PLAN_SEED.md` · D3 roles in `docs/design/MONEY_GOVERNANCE.md`
**Consumers downstream:** S19 (money governance I builds proposals UI next to the board), S21 (EventList = `kind: activity` specialization + RSVP — design the schema so S21 adds columns, not tables)
**Out of scope:** RSVP/events (S21), proposal money fields (S19), attachments UI (P2 hook only), booking integrations (schema hook only)

## 1. Migration `0016_trip_plan_items.sql`

New enum `plan_item_kind`: `lodging | flight | train | activity | other`
(CREATE TYPE — safe in one migration).

`trip_plan_items`:
- `id uuid pk`, `trip_id` fk, `kind plan_item_kind not null default 'other'`
- `title text not null`, `notes text`
- `starts_at timestamptz`, `ends_at timestamptz` (nullable — undated items allowed)
- `external_ref text` (booking-integration hook, no UI semantics yet)
- `attachment_path text` (P2 architectural insurance, NO UI)
- `position int not null default 0` (manual ordering within the board)
- `created_by uuid fk profiles`, `updated_by uuid fk profiles` (P2 audit hook)
- `created_at`, `updated_at` timestamptz defaults

`trip_list_items` (shared checklists — packing/shopping per seed):
- `id`, `trip_id`, `list_name text not null` (free grouping), `label text not null`
- `checked_by uuid null fk profiles`, `checked_at timestamptz null`
- `position int`, `created_by`, `created_at`

**RLS — S17 pattern from day one (this is the review checklist's #1 item):**
- SELECT: `is_trip_member(trip_id)`
- INSERT/UPDATE with check: `is_trip_member(trip_id) AND is_trip_writable(trip_id)`
- DELETE: **restrictive** policy `is_trip_writable(trip_id)` IN ADDITION to the
  member check (FOR ALL + USING leaks deletes — S17 P1-4 lesson; do not repeat)
- Writes by any active member (the board is collective — D3 gives co-admin
  *management* power, not a member write-ban). `updated_by` set via trigger.

No new RPCs needed — plain table writes under RLS (no lifecycle transitions here).

## 2. Flutter (offline-first like expenses)

- Drift: `PlanItems`, `TripListItems` tables (schema v10), outbox sync mirroring
  the expenses repository pattern (optimistic insert, retry, server reconcile).
- `PlanRepository` in feature_split: CRUD + reorder (position swap), checklist
  toggle (`checked_by/checked_at` set/cleared by tapping member).
- UI: **Plan tab** in trip home (after Expenses): board list grouped by date
  (undated section last), kind icon per item (directional, I18N rules),
  add/edit sheet (kind picker, title, notes, optional date range), swipe or
  long-press delete (respects read-only chrome), checklist section below with
  per-list grouping and add-item inline field.
- Read-only after close: same chrome rules as expenses (S17) — add/edit/delete
  disabled in closed/cancelled/unresolved; viewing always allowed.
- ARB strings for everything (en + existing locales get untranslated keys per
  i18n hygiene); mirror-ready layouts.

## 3. Analytics (no titles, no notes — structure only)

`plan_item_created {kind, has_dates}`, `plan_item_updated {kind}`,
`plan_item_deleted {kind}`, `list_item_added`, `list_item_checked {checked}`.
Wire the §8b signal taxonomy as for expenses.

## 4. Verification

- `tool/rls_smoke.dart` additions (state-based):
  - B inserts plan item → PASS; C outsider insert → blocked
  - B INSERT/UPDATE/**DELETE** plan item on closed trip → blocked (all three)
  - B checks a list item → `checked_by = B` (state assertion)
  - ex-member write → blocked
- Unit: repository CRUD + reorder, checklist toggle round-trip, drift migration v9→v10.
- Widget: plan tab renders grouped items; read-only banner disables add.
- `melos run ci` green + smoke full PASS on cloud before merge.

## 5. RUN.md — Slice 18

Migration push (`npx supabase db push`), demo script: add lodging + flight
with dates → reorder → checklist "Packing: sunscreen" → second device sees it
(realtime/sync) → close trip → verify board read-only.

## 6. Reviewer checklist

- [ ] Restrictive DELETE policies present on BOTH new tables (S17 P1-4)
- [ ] No permissive policy recreation that widens an older hardened policy (S17 P1-3)
- [ ] `is_trip_writable` on every write path; SELECT stays member-wide
- [ ] S21-ready: events can extend `trip_plan_items` (kind=activity) without a new table
- [ ] No titles/notes text in analytics
- [ ] ARB-complete; no hardcoded strings; directional layouts
