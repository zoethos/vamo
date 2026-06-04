# Vamo — Architecture (Wave 1)

This document describes the system design for Wave 1: an offline-first Flutter client backed by Supabase, implementing trip-framed bill splitting, solo capture, and branded snapshot sharing. It is the technical companion to [`Vamo_Wave1_Spec.md`](./Vamo_Wave1_Spec.md) and the schema in [`vamo_wave1_schema.sql`](./vamo_wave1_schema.sql).

## Design principles

The architecture follows from a handful of commitments that shape almost every decision downstream:

- **Offline-first.** The local database, not the network, is the UI's source of truth. The app must be fully usable on a plane.
- **Private by default.** Isolation is enforced at the data layer with Row-Level Security, not just in the UI.
- **Vamo never moves money.** Settlements are records and deep-links; there is no payment rail in the system.
- **Deterministic money math.** Integer cents only; settle-up is a pure function with no AI and no floating point.
- **Solo is a group of one.** There is no separate "solo mode" data path — group features simply light up when a second member joins.

## High-level shape

```
┌─────────────────────────── Flutter client ───────────────────────────┐
│                                                                       │
│   UI (screens)  ──reads/writes──▶  Drift (SQLite, source of truth)    │
│        ▲                                   │                          │
│        │ Riverpod providers                │ optimistic write queue   │
│        │                                   ▼                          │
│   settle-up engine (pure)            Sync worker  ◀── Realtime channel │
│                                            │                          │
└────────────────────────────────────────────┼────────────────────────┘
                                              │ HTTPS / WebSocket
                                              ▼
┌──────────────────────────────── Supabase ────────────────────────────┐
│  Auth (email/Apple/Google/phone)   Postgres + RLS   Storage (private) │
│  Edge Functions (daily FX cache)   Realtime          buckets          │
└───────────────────────────────────────────────────────────────────────┘
                                              │
                                              ▼
                        exchangerate.host (daily FX rates)
```

The client owns presentation, the offline cache, and the settle-up computation. Supabase owns durable storage, identity, authorization (RLS), realtime fan-out, file storage, and the scheduled FX fetch. Money movement happens entirely outside the system, via deep-links into third-party payment apps.

## Client architecture

The client is a melos monorepo. `app_core` carries everything cross-cutting — the Supabase client and session handling, the design system (teal/sand theme and shared components), the Drift database, the analytics wrapper, and the entitlement check stub. `feature_split` carries the Wave 1 product surface. Future waves add sibling `feature_*` packages that depend on `app_core` without modifying it.

State is managed with Riverpod; navigation with go_router. The dependency direction is strict: features depend on `app_core`, never the reverse, and never on each other.

### Offline-first data flow

Drift mirrors `trips`, `trip_members`, `expenses`, and `expense_shares` locally, and the UI reads exclusively from Drift. A write follows this path:

1. The UI writes to Drift immediately (optimistic) and the screen updates from local state.
2. The write is appended to a sync queue.
3. A sync worker drains the queue to Supabase, reconciling conflicts **last-write-wins per field**.
4. For any open trip, the client also subscribes to a Supabase Realtime channel so a co-editor's changes stream in and merge into Drift.

This keeps the app responsive and fully functional offline; the network is a background reconciliation concern, not a request/response dependency in the hot path.

## Backend architecture

Supabase provides Postgres with Row-Level Security, Auth across four providers, Storage, Realtime, and Edge Functions. The entire authorization model lives in the database so that no client can bypass it.

### Data model

Seven tables plus one derived view. All monetary columns are integer cents (`bigint`).

| Entity | Purpose | Key points |
|--------|---------|------------|
| `profiles` | 1:1 with `auth.users` | auto-created by the `handle_new_user` signup trigger; holds display name, avatar, base currency |
| `trips` | a trip (solo or group) | `owner_id`, `base_currency`, `visibility` (default `private`) |
| `trip_members` | membership roster | composite PK `(trip_id, user_id)`; `role` and `status` (active/invited/left) |
| `invites` | share-link tokens | random `token`, `expires_at` (30d), `max_uses`/`uses` counters |
| `expenses` | a logged cost | original `amount_cents`/`currency` **and** converted `base_cents` + `fx_rate` snapshot |
| `expense_shares` | per-member split | `share_cents`; shares must sum to the expense's `base_cents` |
| `settlements` | mark/confirm records | `from_user`/`to_user`, `amount_cents`, `status` (marked/confirmed), `method` |
| `trip_balances` (view) | net position per member | derived; positive = group owes the member, negative = member owes |

The `trip_balances` view computes each active member's net as `paid − owed + settled_out − settled_in`, all in trip base cents. It is the single input to the settle-up engine.

### Authorization (RLS)

Every table has RLS enabled. The pivot is the `is_trip_member(trip_id)` helper — a `security definer`, `stable` SQL function that checks active membership. It is `security definer` deliberately: referencing `trip_members` directly inside a `trip_members` policy would recurse, so the function runs with elevated rights to break the cycle cleanly.

Policy summary:

- **profiles** — any authenticated user can read basic profiles (needed to render member names/avatars); you can only update your own.
- **trips** — members (or the owner) can read; any authenticated user can create and becomes the owner; only the owner can update.
- **trip_members** — members can read the roster; you may insert *yourself* (e.g. the owner on trip creation). General joining does **not** go through an insert policy.
- **invites** — members can read and create invites for their trips.
- **expenses / expense_shares / settlements** — full access scoped to trip members.

Joining a trip is handled by the `join_trip(token)` function rather than a direct insert. It is `security definer` so a not-yet-member can be added safely: it validates the token (exists, not expired, uses remaining), upserts the caller as an active member, increments the use counter, and returns the trip id. This is the only sanctioned path for an outsider to gain membership.

### FX rates

A daily Edge Function (scheduled) fetches rates from exchangerate.host and caches them. When an expense is logged in a non-base currency, the client reads the day's rate, computes `base_cents = round(amount_cents * fx_rate)`, and stores the original amount, the `base_cents`, and the `fx_rate` together on the expense. Because the rate is snapshotted at spend time, historical balances never drift when rates change later.

### Storage

Two private buckets: avatars and snapshot images. Nothing is public. When a user chooses to share a snapshot, the client uploads the rendered PNG and produces a signed URL with a limited lifetime — the only way image data leaves the private boundary.

## The settle-up engine

Settle-up is the trust-critical core, so it is a pure, deterministic, dependency-free Dart function — easy to unit-test and impossible to get subtly wrong with floats.

Given each member's `net_cents` from `trip_balances`, it splits members into creditors (net &gt; 0) and debtors (net &lt; 0), sorts both largest-first, and greedily matches the largest debtor against the largest creditor, emitting a "X pays Y" transaction for the smaller of the two amounts and advancing whichever side hits zero. The result is the **minimum number of transactions** that clears the trip.

```
while debtors and creditors remain:
    pay = min(debtor.amount, creditor.amount)
    emit Settlement(from: debtor, to: creditor, cents: pay)
    debtor.amount  -= pay
    creditor.amount -= pay
    advance whichever side reached zero
```

Penny-rounding residue from FX conversion (a cent or two) is acceptable and assigned to the largest share. The engine is covered by fixtures for equal split, custom split, multi-payer, multi-currency, and a 3-person cycle.

A settlement, once computed and acted on, is recorded with `status = 'marked'` and balances update optimistically; the client deep-links to Venmo / PayPal / Wise with the amount prefilled where supported. The recipient can later set `status = 'confirmed'`. No money flows through Vamo at any point.

## Branded snapshot share

The snapshot is the seed of the growth loop. A card widget composes the trip name, dates, total spent, member avatars, and the Vamo wordmark over a teal/sand background, then `RenderRepaintBoundary` rasterizes it to a PNG. The image is handed to the system share sheet (and uploaded to the private bucket with a signed URL when shared externally). Sharing fires the `snapshot_shared` analytics event.

## Analytics

PostHog instruments the North-Star loop with seven events: `trip_created`, `member_invited`, `invite_accepted`, `expense_added`, `settle_marked`, `settle_confirmed`, and `snapshot_shared`. These map directly onto the acquisition → activation → sharing funnel and are the primary signal for whether the loop is working.

**Product signals (Slice 11 / milestone Signals / spec §8b)** add a listening stack: router `screen_viewed` via root `NavigatorObserver` on named GoRoutes, `AppErrorState` / `AppEmptyState` friction events, `FlowTracker` on create-trip / add-expense / invite-button (not tab mount), `action_failed` on write failures (sanitized PostgREST/network codes via `reportActionFailed`), three intention doors (Plus, trip map, recap), and suggest-a-feature rows in `suggestions` (RLS insert/read-own; text never in PostHog). `notify_me_opted_in` is identified-user PostHog only — no notify list in Postgres yet.

## Security & privacy posture

Privacy is enforced at the lowest layer that can enforce it. RLS gates every row by trip membership; the two `security definer` functions are the only places that step outside a caller's own rights, and both are narrowly scoped (membership check; token-validated join). Snapshot images are private until the user explicitly shares via a signed URL. The billing principle — upgrade anytime, downgrade or cancel at cycle end, no dark patterns — is carried from day one even though paid tiers arrive later; the entitlement check is wired now as a stub.

## Repository growth path

One git repository, two toolchains, one schema. Melos manages the Dart subtree, npm workspaces + Turborepo will manage the TypeScript subtree; they never overlap. Dart and TS share no source code — the cross-language contract is `supabase/` (one migration chain both sides consume; types can be generated from it on each side). Items marked *(planned)* exist as placeholders or not at all until their wave begins — scaffolding ahead of the gate is deliberately avoided.

```
vamo/                          one git repo
├─ app/                        Flutter shell — Wave 1+
├─ packages/                   Dart packages (Melos workspace)
│  ├─ app_core/                cross-cutting: auth, db, sync, analytics, design, entitlements
│  ├─ feature_split/           Wave 1 — SplitTrip, capture, snapshot, signals
│  ├─ feature_events/          Wave 2 — EventList (planned)
│  ├─ feature_board/           Wave 2 — TripBoard (planned)
│  ├─ feature_map/             Wave 3 — TripMap, ghost-trail, Tally (planned)
│  ├─ feature_reel/            Wave 4 — TripReel, media merge, Atlas (planned)
│  └─ feature_replay/          Wave 5 — branching replay, Orbit (planned)
├─ web/                        TypeScript side (npm workspaces + Turborepo)
│  ├─ apps/
│  │  ├─ share-pages/          Wave 2–3 — view-before-install, branded share pages (planned)
│  │  └─ operator-console/     post Wave-3 gate — B2B operator content console (planned)
│  └─ packages/                shared TS types/UI as @vamo/* (planned)
├─ supabase/                   THE shared contract: schema, migrations, edge functions
├─ docs/                       specs, QA checklists, runbooks, templates
└─ melos.yaml                  Dart workspace config (does not see web/)
```

Rules that keep this healthy: every feature is a sibling `feature_*` package depending on `app_core`, never on each other; every schema change is a numbered migration in `supabase/migrations/` applied via `supabase db push` (never ad-hoc SQL); the B2B operator track extends this tree (a role, entitlements, one web app) — it never forks it. CI splits by path: Dart jobs trigger on `app/**` and `packages/**`, web jobs on `web/**`. Exit condition for the single repo: a dedicated team with its own release cadence on the operator side — not before.

## Web strategy

Mobile-first does not mean mobile-only. Vamo ships web surfaces in step with the features that need them, against the *same* Supabase backend — every web client obeys the same RLS policies and hits the same API, so nothing about the backend changes to support the web. Three distinct web surfaces, each with its own technology and trigger:

| Surface | What it is | Technology | Arrives |
|---------|-----------|------------|---------|
| **Share & preview pages** (public) | View-before-install trip preview behind invite links; branded snapshot/recap share pages that unfurl properly on socials and load instantly with no install | Next.js (SSR for speed, link unfurls, SEO), Vercel free tier | Wave 2–3, with the first shareable surfaces |
| **PC dashboard** (authenticated) | The "comfortable big screen" home for travel history: Tally stats, Atlas journey archive, the Orbit globe | Flutter Web — same codebase and packages as the app, compiled for browser | Waves 3–5, as Tally/Atlas/Orbit ship |
| **Interactive replay runtime** (public, opt-in shares) | The branching "choose whose path" journey replay, playable in any browser from a shared link | Web runtime (already named in the scaling triggers) | Wave 5 |

The split is deliberate: public pages need SSR and crawlability, which Flutter Web is poor at — so they go to Next.js; the logged-in dashboard reuses the existing Dart packages (settle-up engine, models, Supabase client) at near-zero marginal cost — so it stays Flutter. The viral loop depends on the public tier: an invite or replay link that demands an install before showing anything would kill conversion at the most valuable moment.

## What's deliberately out (later waves)

Live location, ghost-trail, action-cam capture, recap video, and the interactive branching **journey replay** — the eventual killer feature — are out of Wave 1. So are itineraries, events, the Tally/Atlas/Orbit surfaces, and the web surfaces above (the "view-before-install" preview is the first to arrive). The Wave 1 data model and package boundaries are designed so these arrive as additive `feature_*` packages and new tables, without reworking `app_core` or the existing schema.
