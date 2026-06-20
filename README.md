<p align="center">
  <img src="./vamo_roadtrip_icon_cheering_friends.svg" alt="Vamo" width="140"/>
</p>

<h1 align="center">Vamo</h1>

<p align="center"><b>Trips, together. Split the costs, capture the journey, share the story.</b><br/>
<i>Si va?</i></p>

---

Vamo is a trip companion for solo travellers and groups — any trip, from a daily
commute to a year's big holiday. **Wave 1** ships the wedge: **SplitTrip**
(trip-framed bill splitting, multi-currency, minimal settle-up), **solo capture**
(notes and photos), and a **branded snapshot share** with destination theme packs
that seeds the growth loop. Private by default. Vamo never moves money — it
deep-links to the payment apps you already use.

The endgame (waves 3–5) is the **interactive journey replay**: every member's
GPS trace merged on one timeline, action-cam footage pinned to the route, and a
branching "choose whose path to follow" replay of the whole trip. No incumbent
does this. The wedge funds the moat.

## Status

**Wave 1 code-complete** — running on real hardware (Android), email auth live
(OTP code + PKCE magic link via custom SMTP), cloud schema hardened through
migration `0007`. Remaining before internal testers: RLS QA pass, store internal
builds, and the name/domain decision. Slice 13 (i18n/RTL readiness) is specced
and next.

| Wave | Ships | Status |
|------|-------|--------|
| 1 | SplitTrip + capture + snapshot themes + product signals | ✅ built |
| 2 | EventList + TripBoard · AI theme resolver (global cache) · web share pages | next |
| 3 | TripMap + ghost-trail · Tally/Wrapped · **go/kill gate** (incl. B2B operator track) | — |
| 4 | TripReel + action-cam merge · Atlas · immersion imagery | — |
| 5 | Vamo suite · branching replay · Orbit/Constellations | — |

## Tech stack

| Layer | Choice |
|-------|--------|
| Client | Flutter (Dart ≥3.6) — melos monorepo |
| State / nav | Riverpod · go_router |
| Local cache | Drift (SQLite) — the offline-first source of truth |
| Backend | Supabase — Postgres + RLS, Auth, Storage, Realtime, Edge Functions |
| Auth | Email OTP/magic link (custom SMTP via Brevo); Apple/Google/phone wired |
| FX rates | exchangerate.host, cached daily, snapshotted per expense |
| Analytics | PostHog (EU) — North-Star funnel + product signals |
| Web tier (future) | Next.js + Turborepo under `web/` — scaffold only until Wave 2 |
| Money | Integer cents everywhere — never floats |

## Repository layout

One repo, two toolchains, one schema (see `ARCHITECTURE.md` → *Repository growth path*):

```
vamo/
├── app/                     # Flutter shell (entry, routing, platform config)
├── packages/
│   ├── app_core/            # auth, Supabase client, Drift, sync, analytics,
│   │                        #   design system, error presentation, FX
│   └── feature_split/       # Wave 1 surface: trips, expenses, balances,
│                            #   settle-up, capture, snapshot + themes, signals
├── web/                     # TS side (npm workspaces + Turborepo) — scaffold;
│   ├── apps/                #   share-pages (W2–3), operator-console (post-W3)
│   └── packages/            #   @vamo/* shared TS — created when needed
├── supabase/
│   ├── migrations/          # 0001–0007: schema, RPCs, RLS, hardening — the
│   │                        #   single cross-language contract
│   └── functions/           # fx-rates cache, send-auth-email hook (dormant)
├── docs/                    # plans & runbooks (see index below)
├── ARCHITECTURE.md          # system design + growth path + web strategy
└── Vamo_*.{md,docx,xlsx}    # spec, build plan, backlog, roadmap, business plan, model
```

`app_core` holds everything cross-cutting; each wave adds sibling `feature_*`
packages that depend on `app_core`, never on each other.

## Getting started

Prerequisites: Flutter (stable ≥3.27), `dart pub global activate melos`,
Supabase CLI, a Supabase project.

```bash
# 1. Backend — apply ALL migrations in order (never ad-hoc SQL)
supabase link --project-ref <your-ref>
supabase db push

# 2. Client config
cp .env.example app/.env       # then fill values — never commit app/.env

# 3. Run
melos bootstrap
melos run build_runner         # codegen (Drift) — required before analyze/test
cd app && flutter run          # phone, or: flutter run -d chrome --web-port 3000
```

Auth needs two dashboard settings: custom SMTP (templates only persist with it —
see `docs/AUTH_EMAIL_TEMPLATE.md`) and Redirect URLs containing
`app.vamo://login-callback` + your web origin. Enable "RLS on new tables".

Windows note: keep project and caches on the **same drive** (`PUB_CACHE`,
`GRADLE_USER_HOME`) or Kotlin incremental compilation fails with
"different roots".

## Load-bearing conventions

Break these and the money math, privacy, or brand guarantees break with them.

**Money is integer cents.** No floats in any expense/share/balance/settlement
path. Multi-currency stores original `amount_cents`/`currency` **and**
`base_cents` + `fx_rate` snapshotted at spend time.

**The share invariant.** `sum(expense_shares.share_cents) == expenses.base_cents`
— enforced by the app on write.

**Private by default.** RLS gates every row via `is_trip_member()`; membership
only via the `create_trip`/`join_trip` security-definer RPCs. Storage buckets
are private; sharing is explicit signed URLs.

**Vamo never moves money.** Settlements are mark-and-confirm records;
payment happens in external apps via deep links.

**Offline-first.** Drift is the UI's source of truth; writes are optimistic and
queued; the sync worker reconciles (idempotent, dead-lettering, flush-before-pull).

**Errors never leak the stack.** Users see catalogued messages only — no
exception text, no framework or vendor names in UI strings (`showActionError`
is the single path; it also fires telemetry). Raw detail goes to logs only.

**The watermark is permanent.** Snapshot themes customize everything except the
Vamo wordmark — customization is sold, visibility never is.

**Schema changes are numbered migrations** applied with `supabase db push` —
the database and the code must never live in different worlds.

**Externalize strings; directional layouts.** i18n from the start;
`EdgeInsetsDirectional`/start-end for RTL readiness (`docs/I18N_PLAN.md`).

## Testing

```bash
melos run ci     # build_runner → analyze → test, in the required order
```

Highest-value suites: settle-up engine (minimum-transaction guarantee), FX math
and stale-cache fallback, sync worker failure modes, error sanitization
(no `PGRST`/vendor strings reach UI), theme resolver (word-boundary, diacritics),
and snapshot goldens per theme pack.

## Analytics — the listening stack

Four layers (spec §8b): **North-Star funnel** (7 events: `trip_created` →
`snapshot_shared`), **UX friction** (`screen_viewed`, `error_shown`,
`flow_abandoned`, `action_failed` with sanitized codes), **intention doors**
(Plus/map/recap teasers + `notify_me_opted_in`), **suggestions** (text stays in
Postgres, never in analytics). Set `POSTHOG_API_KEY` in `app/.env`; without it
events print to the debug console.

## Documentation index

| Doc | What |
|-----|------|
| `ARCHITECTURE.md` | system design, repository growth path, web strategy |
| `Vamo_Wave1_Spec.md` | feature contract incl. product signals + error policy |
| `Vamo_Wave1_BuildPlan.md` / `Vamo_Wave1_Backlog.xlsx` | slices 0–13, estimates, acceptance |
| `docs/AI_THEMING_SPEC.md` | AI theme resolver + global destination cache (Wave 2) |
| `docs/I18N_PLAN.md` | RTL (ar/he) + script readiness (zh/hi/ja/ru) |
| `docs/AUTH_EMAIL_TEMPLATE.md` | OTP-first email templates + SMTP notes |
| `docs/RLS_QA.md` / `docs/SHIP_INTERNAL.md` | pre-ship checklists |
| `docs/business/Vamo_Roadmap.docx` | five waves, gates, extras ledger |
| `docs/business/Vamo_Business_Plan.docx` / `docs/business/Vamo_Financial_Model.xlsx` | the business case (3 scenarios + operator track) |

---

<p align="center"><i>Built solo, AI-accelerated, on a €10K bet.</i> 🚐</p>
