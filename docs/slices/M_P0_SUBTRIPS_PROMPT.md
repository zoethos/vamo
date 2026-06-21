# M-P0 — Subtrips: toggle + peer-owned parallel plan items

**Why.** First buildable piece of Subtrips (`docs/specs/cycle5-subtrips-followme.md`). Establishes the
**peer permission scope** (the crux) and the admin toggle, so a subgroup can plan a parallel itinerary
without polluting the main plan. **No money, no parent-timeline rollup, no replay** — those are P1/P2.

**Scope = P0.** Admin toggle gates subtrip creation; when on, any trip member creates a subtrip, picks
participants, and adds **parallel plan items** that **any subtrip member can edit** (no admin).

## A. Schema (migration via `supabase migration new`)
- `trips`: `subtrips_enabled boolean not null default false` — the gate.
- `subtrips` table: `id uuid pk`, `trip_id uuid not null references trips`, `name text not null`,
  `created_by uuid`, `created_at timestamptz default now()`.
- `subtrip_members` table: `subtrip_id uuid references subtrips on delete cascade`, `user_id uuid`,
  `pk (subtrip_id, user_id)`. (Membership in the *parent trip* is a precondition — enforce in the
  create RPC.)
- `trip_plan_items`: add `subtrip_id uuid null references subtrips(id) on delete cascade`
  (**null = main-trip item; set = belongs to that subtrip**). No new `plan_item_kind` values.
- Helper: `is_subtrip_member(p_subtrip_id uuid) returns boolean` (`auth.uid()` ∈ `subtrip_members`).

## B. Permissions — the peer scope (the point of this slice)
- **Create a subtrip:** an RPC `create_subtrip(p_trip_id, p_name, p_member_ids[])`, `security definer`:
  require `is_trip_member(p_trip_id)` **and** `trips.subtrips_enabled`; all `p_member_ids` must be active
  trip members; creator auto-included. `revoke from public; grant authenticated`.
- **Toggle:** only owner/co-admin (`can_edit_trip_content`) may set `subtrips_enabled` (gate it in the
  existing trip-update path/guard).
- **Subtrip plan items — peer editable:** extend the `trip_plan_items` write policy/guard so a write is
  allowed when `can_edit_trip_content(trip_id)` **OR** `(subtrip_id is not null AND
  is_subtrip_member(subtrip_id))`. So **any subtrip member** can add/edit/reorder/delete *that subtrip's*
  items — no admin — while main-trip items stay owner/co-admin only.
- **Read:** subtrip + its items visible to trip members (P0 — keep it simple; "hide subtrips from
  non-participants" is a P1 decision).

## C. Client
- **Toggle** in trip settings (owner/co-admin): "Allow subtrips."
- When enabled, the Plan tab offers **"New subtrip"** → name + a **member multi-select** (active trip
  members) → `create_subtrip`. Subtrips render as labeled groups/sections; selecting one scopes the
  add-plan-item flow to that subtrip (`subtrip_id` threaded through `PlanItemInput` → repo → sync).
- Plan-item create/edit (the existing sheet) gains an optional `subtripId`; the existing
  `plan_repository` / `planItemUpsert` path carries it (don't drop it on partial upsert/reorder).
- Peers see + edit a subtrip's items live via the existing realtime/sync.

## D. Tests
- **Dart:** `subtripId` threads through `PlanItemInput` → payload → Drift (no drop on reorder); subtrip
  create flow; plan list groups items by subtrip.
- **rls_smoke:** with `subtrips_enabled`, a member creates a subtrip; **a subtrip member (non-admin) can
  add/edit that subtrip's plan items**; a **non-member of the subtrip cannot**; a member **cannot create
  a subtrip when the toggle is off**; only owner/co-admin can flip the toggle; main-trip items still
  reject non-admins.

## E. Guardrails / done =
- The peer scope is the deliverable — verify a plain member (no co-admin) edits subtrip items but not
  main-trip items.
- Drift `schemaVersion` bump + migration step for `subtrip_id`; thread it through sync (incl.
  reorder/partial payloads).
- Migration to **staging** (`sfwziwcuyctxvidivnsh`, not prod) + `rls_smoke` green incl. the peer cases;
  `melos run ci` green; goldens on **Linux** if the plan surface changes; watch the `AppColors` ratchet.
- **No money** in P0 — subtrip expenses + subset-split reconciliation are P1 (reuses the S50 server
  recompute over the subtrip roster).

## Notes
- Branch base off `main`; own worktree.
- P1 = parent-timeline rollup + per-subtrip expenses (subset-split). P2 = subtrip replay branch (Trip Map).
- Pairs with the consolidated role/RLS pass (owner / co-admin / member / **subtrip-peer** / guest).
