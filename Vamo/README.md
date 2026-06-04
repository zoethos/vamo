# Vamo

> Trips, together. Split the costs, capture the journey, share the story.

Vamo is a trip companion app for solo travellers and groups. **Wave 1** ships the foundation: **SplitTrip** (trip-framed bill splitting with multi-currency support and minimal settle-up), **solo trip capture** (notes and photos), and a **branded snapshot share** that seeds the app's growth loop. Everything is private by default; Vamo never moves money — it deep-links to the payment apps you already use.

This README covers how the repository is laid out and how to get a dev environment running. For the system design see [`ARCHITECTURE.md`](./ARCHITECTURE.md); for the full feature contract see [`Vamo_Wave1_Spec.md`](./Vamo_Wave1_Spec.md) and the executable backlog in [`Vamo_Wave1_Backlog.xlsx`](./Vamo_Wave1_Backlog.xlsx).

## Status

Wave 1, pre-alpha. Target is an internal build (TestFlight / Play internal) of the SplitTrip + solo-capture + snapshot scope. Live location, ghost-trail, action-cam sync, and the interactive journey replay are deliberately **out of scope** for Wave 1 and land in later waves.

## Tech stack

| Layer | Choice |
|-------|--------|
| Client | Flutter (Dart) |
| State | Riverpod |
| Navigation | go_router |
| Local cache | Drift (SQLite) — the offline-first source of truth |
| Backend | Supabase — Postgres, Auth, Storage, Realtime, Edge Functions |
| Auth | Email, Apple, Google, phone |
| FX rates | exchangerate.host (free), cached daily, snapshotted per expense |
| Analytics | PostHog |
| Money | Integer cents everywhere — never floats |

There is **no Mapbox in Wave 1**: the snapshot is a styled card, not a live map.

## Repository layout

The Flutter client is a melos-managed monorepo. Backend lives alongside it as SQL migrations and edge functions.

```
vamo/
├── app/                     # Flutter application shell (entry point, routing, DI)
├── packages/
│   ├── app_core/            # auth, Supabase client, design system, Drift, analytics
│   └── feature_split/       # SplitTrip: trips, expenses, balances, settle-up, snapshot
├── supabase/
│   ├── migrations/          # vamo_wave1_schema.sql and successors
│   └── functions/           # edge functions (e.g. daily FX rate cache)
├── Vamo_Wave1_Spec.md       # Wave 1 feature contract
├── Vamo_Wave1_Backlog.xlsx  # sequenced, estimated task backlog
├── Vamo_Wave1_BuildPlan.md  # sprint narrative
├── vamo_wave1_schema.sql    # runnable Supabase schema + RLS
├── ARCHITECTURE.md          # system design
└── README.md                # you are here
```

`app_core` holds everything cross-cutting; `feature_split` holds the Wave 1 product surface. Later waves add their own `feature_*` packages without touching `app_core`'s contracts.

## Getting started

### Prerequisites

- Flutter SDK (stable channel) and Dart
- [melos](https://melos.invertase.dev/) for the monorepo: `dart pub global activate melos`
- [Supabase CLI](https://supabase.com/docs/guides/cli)
- A Supabase project (cloud or local via `supabase start`)

### 1. Stand up the backend

```bash
# from repo root, with the Supabase CLI linked to your project
supabase db push                 # or paste vamo_wave1_schema.sql into the SQL editor
```

This creates `profiles, trips, trip_members, invites, expenses, expense_shares, settlements`, the `trip_balances` view, the `handle_new_user` signup trigger, the `is_trip_member()` / `join_trip()` helper functions, and all Row-Level Security policies. Enable the four auth providers (email, Apple, Google, phone) in the Supabase dashboard, and create two **private** storage buckets: one for avatars and one for snapshot images.

After running it, validate isolation with Supabase's RLS tester — a non-member must not be able to read a trip.

### 2. Configure the client

Copy the example env and fill in your project values:

```bash
cp .env.example .env
```

| Variable | Description |
|----------|-------------|
| `SUPABASE_URL` | Your project URL |
| `SUPABASE_ANON_KEY` | Public anon key |
| `POSTHOG_API_KEY` | PostHog project key |
| `FX_RATES_FUNCTION_URL` | Endpoint of the daily FX cache function |

Never commit `.env` or service-role keys.

### 3. Run

```bash
melos bootstrap          # resolve and link all packages
melos run build_runner   # codegen for Drift / Riverpod
flutter run              # from app/
```

## Conventions

A few rules are load-bearing — break them and the money math or privacy guarantees break with them.

**Money is integer cents.** No floats anywhere in the expense, share, balance, or settlement paths. Multi-currency expenses store both the original `amount_cents`/`currency` and the converted `base_cents` plus the `fx_rate` snapshotted at spend time. All balances and settle-up run in the trip's base currency.

**The share invariant.** For every expense, `sum(expense_shares.share_cents) == expenses.base_cents`. This is enforced in the app on write — the database documents it but does not enforce it, so client code must.

**Private by default.** Every trip is `visibility = 'private'`; access is gated by RLS through `is_trip_member()`. Snapshot images live in a private bucket and are only ever exposed via a signed URL when the user explicitly shares.

**Vamo never moves money.** Settlements are mark-and-confirm records; payment happens via deep-links to Venmo / PayPal / Wise. There is no payment processing in the codebase by design.

**Offline-first.** Drift is the UI's source of truth. Writes are optimistic and queued; a sync worker reconciles to Supabase (last-write-wins per field). See [`ARCHITECTURE.md`](./ARCHITECTURE.md) for the sync model.

**Externalize strings.** i18n is wired from the start; no hard-coded user-facing copy.

## Testing

The settle-up engine and FX math are pure, deterministic, and high-value — they carry the most unit-test coverage:

```bash
melos run test
```

Required fixtures for the settle-up engine: equal split, custom split, multi-payer, multi-currency, and a 3-person cycle. The engine must always produce the **minimum number of transactions** that clears the trip.

## Analytics

The North-Star loop is instrumented with seven PostHog events: `trip_created`, `member_invited`, `invite_accepted`, `expense_added`, `settle_marked`, `settle_confirmed`, `snapshot_shared`. Set `POSTHOG_API_KEY` in `app/.env` (see `.env.example`); verify all seven in PostHog Live before shipping ([`docs/SHIP_INTERNAL.md`](./docs/SHIP_INTERNAL.md), [`docs/RLS_QA.md`](./docs/RLS_QA.md)).

## Related documents

- [`ARCHITECTURE.md`](./ARCHITECTURE.md) — system design and data model
- [`Vamo_Wave1_Spec.md`](./Vamo_Wave1_Spec.md) — Wave 1 feature contract
- [`Vamo_Wave1_BuildPlan.md`](./Vamo_Wave1_BuildPlan.md) — sprint plan
- [`Vamo_Wave1_Backlog.xlsx`](./Vamo_Wave1_Backlog.xlsx) — task backlog with estimates and dependencies
- [`Vamo_Roadmap.docx`](./Vamo_Roadmap.docx), [`Vamo_Business_Plan.docx`](./Vamo_Business_Plan.docx) — product and business context
