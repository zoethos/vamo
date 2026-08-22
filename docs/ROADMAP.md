# Vamo delivery roadmap

**Updated:** 12 August 2026 · `main` at `181f546`

This is the **execution layer**: what is in flight, who owns it, what blocks it, and what
is applied to which database. It sits beneath the product roadmap, which sets direction.

| Layer | Document | Answers |
| --- | --- | --- |
| Product direction | [`business/Vamo_Roadmap.docx`](business/Vamo_Roadmap.docx) | What Vamo becomes, in five waves, with go/kill gates |
| **Execution (this file)** | `docs/ROADMAP.md` | What to do today, and what is blocked on what |
| Place-data programme | [`architecture/DATA_ACQUISITION_STRATEGY.md`](architecture/DATA_ACQUISITION_STRATEGY.md) | The rights model and Confluendo boundary |

Two agents and one owner work from this file, so it is only useful if it stays true:
**update it when something merges, promotes, or is parked.** If work is not listed here,
it is not queued. `slices/README.md` is historical Wave 2 evidence, not a roadmap.

## Where we are

**Waves 1 and 2 shipped.** The wave model was then deliberately amended: the
**wave retag decision of 2026-06-22**, recorded in
[`design/NAVIGATION_MAP.md`](design/NAVIGATION_MAP.md), moved **Trip Map and Trip Wrapped
out of Wave 3 into core flow** — built now, because the progressive map is part of the
end-to-end flow testers must exercise. What Wave 3 actually defers is the **heavy
external-integration layer** (live transit / travel-means status), not the map.

`Vamo_Roadmap.docx` predates that decision and still tags Map as Wave 3. Where they
conflict, **`NAVIGATION_MAP.md` and the slice prompts are current.**

Consequences for what is parked below:

- **Trip Map P0** — core flow, built. Always-on progressive map (`slices/TRIP_MAP_P0_PROMPT.md`).
- **Member trails** — **P1**, blocked on the location-sharing infrastructure from "Follow me"
  (`specs/cycle5-subtrips-followme.md`), not on a wave gate.
- **Trip Wrapped** — core flow, with the map as its data spine; deferred on a reliable
  close-time data contract.

The identity-linking work in flight is Wave 1–2 correctness debt being paid before the
tester cohort grows. Confluendo is a **supporting programme**, not a wave — it serves place
resolution for the map and Visit POIs. It has never been located in the delivery structure,
which is why it competed with product work rather than serving it.

---

## Destination: closed beta

Everything below serves one near-term goal — **widening closed beta** — which is gated on the
six operational items in [`operations/LAUNCH_GATES.md`](operations/LAUNCH_GATES.md):

| # | Gate |
| --- | --- |
| 1 | Email SPOF closed |
| 2 | Crashlytics proof |
| 3 | App Links SHA |
| 4 | DR basics |
| 5 | Scenario sim + k6 |
| 6 | Infra upgrade |

Feature work may merge while these are open; **beta must not widen until every gate is met.**
After that, the 14-day [`operations/BETA_SCORECARD.md`](operations/BETA_SCORECARD.md) decides
what comes next — Cycle 4 UX follows beta evidence, not ahead of it.

**Gap: the gates document defines the evidence each gate needs but records no current status.**
Gate 1 is believed open (`RESEND_API_KEY` unset, so the Brevo→Resend fallback is coded and
deployed but inert). The others are unknown. Establishing and recording those six statuses is
the highest-value hour available right now — without it, "how far from beta" is unanswerable.

---

## Now

| # | Item | Owner | Blocked by |
| --- | --- | --- | --- |
| 1 | Verify the next scheduled Production `trip-lifecycle-jobs` heartbeat carries a meaningful `identity_integrity.status` | Codex | 06:00 UTC run |
| 2 | Auth settings: disable Phone sign-in, enable Manual Linking, verify linking Google + Apple to an existing email account | Owner | item 1 |
| 3 | Rebase #288 (next-up plan item) onto current `main`, rerun CI, then review for merge | Codex | nothing |
| 4 | **Establish and record the status of all six launch gates** in `operations/LAUNCH_GATES.md` | Codex (audit) + Owner (ops facts) | nothing |

**Item 1 — the status is now meaningful.** #287 merged and `trip-lifecycle-jobs` was
redeployed to Production from `181f546` on 12 August. Its first post-deploy scheduled
heartbeat must be read after 06:00 UTC: `attention` identifies which aggregate counter
tripped; `ok` means none did. The pre-deploy baseline at 06:00 UTC was all zero.

**Item 4 answers "how far from beta".** The gates define required evidence but record no
status, so the distance to the goal everything else serves is currently unknown. Codex can
establish most of it from the repo and CI; only the ops facts — secrets provisioned, SHA
registered, DR drill run — need the owner. Do this before choosing what to build next.

**Item 2 is the launch risk.** Until identity linking is configured, one person signing in
two ways becomes two trip members with split expenses and balances. Merging such accounts
after real money exists is partly unresolvable, so this precedes everything else.

### Post-cron decision plan

**Trigger:** shortly after the next 06:00 UTC Production run. This is a read-only check;
do not invoke the worker manually, rotate `CRON_SECRET`, apply a migration, or change Auth
before its result is known.

| Result | Immediate action | Stop condition |
| --- | --- | --- |
| A fresh heartbeat has `identity_integrity.status = "ok"` | Codex records the timestamp and aggregate counters. Owner performs the Auth settings change: disable Phone sign-in; enable Manual Linking; then, in a controlled test account, link Google and Apple to an existing email account and confirm one identity/member result. | Stop before any unrelated migration promotion or tester build upload; record the test result in the roadmap/runbook first. |
| A fresh heartbeat has `status = "attention"` | Codex reports only the named aggregate `attention_counters`; investigate the duplicate/relay condition before changing Auth settings. | Do not alter Auth settings, invoke the worker, or expose identities in the heartbeat. |
| The expected heartbeat is missing or the worker reports any other status | Codex reports the fact and inspects deployment/log evidence read-only. | Do not retry by manually invoking the Production worker and do not change `CRON_SECRET`. |

**After a successful Auth proof:** choose one human promotion window for #284 (custom expense
split) or #286 (function privilege convergence); run its existing Staging-then-Production
packet unchanged. #288 remains independent: Codex can rebase, validate, and prepare it for
merge without waiting for the cron result.

### Completed 12 August

- Production `identity_integrity` baseline read after the scheduled run: every aggregate
  counter was `0`.
- #287 merged; its escalation changes are deployed to Production. No migration, Auth setting,
  secret, or manual worker invocation was involved.

---

## Next — independent, any order

| Item | What it needs |
| --- | --- |
| **#284 promotion** — custom expense split | One promotion window. Runbook: `operations/CUSTOM_EXPENSE_SPLIT_PROMOTION.md` |
| **#286 promotion** — public function privilege convergence | One promotion window. Runbook: `operations/FUNCTION_PRIVILEGE_CONVERGENCE_PROMOTION.md` |
| **Per-type plan forms** | Train, Flight, Lodging still use generic title/notes. Flight provider lookup is explicitly out of scope |
| **Trip hero layout** | Replace the measured `Stack` + post-frame `setState` with slivers; fold in the quick-actions rework |

One migration per promotion window, Staging before Production, in the same window.

---

## Database state

Established by object probe, **not** by the migration ledger — see Standing constraints.

| Migration | Staging | Production |
| --- | --- | --- |
| … through `20260810140000` (place-data batch, incl. PostGIS) | applied | applied |
| `20260811120000_identity_integrity_signal` | applied | applied |
| `20260811130000_custom_expense_split` | **not applied** | **not applied** |
| `20260811140000_function_privilege_convergence` | **not applied** | **not applied** |

Interim targeted revokes are applied in both environments: seven service-only functions in
both, plus `identity_integrity_summary()` in Production. Production still exposes ~80
functions to `anon`/`authenticated`; #286 is the durable convergence.

Environment markers: Staging reports `staging`, Production reports `production`.

---

## Parked by decision

- **Confluendo municipality programme.** All code merged. Frozen after the agreed
  single-package Italy proof (~1–2 days of operational work, whenever chosen).
  **Do not start full-Italy delivery** — that is ~316 approval cycles at 25 municipalities
  per package, and needs a bulk-delivery mode keyed to rights class first.
- **MW0 — migration-ledger reconciliation.** The read-only inventory can happen any time;
  the mutating `supabase migration repair` needs its own window.
- **Member map trails (Map P1)** — needs the location-sharing infrastructure from "Follow me"
  (`specs/cycle5-subtrips-followme.md`) and the consent model that goes with it. The map stays
  aggregate-only until that lands. Not a wave gate.
- **Trip Wrapped** — core flow, but deferred until the close-time data contract is reliable.
  It consolidates from the Map data spine and must not create a parallel one.
- **External-integration layer** (live transit / travel-means status) — the part of Wave 3
  genuinely deferred per the 2026-06-22 retag.
- **API tier / service decomposition.** Justified by schema-release coupling, not by load;
  see `architecture/` and the parallel-scaling analysis. Not this quarter.

---

## Owed but unscheduled

- **Subtrips real-device v24 → v25 migration pass.** A release gate, manual QA rather than
  a build task, and currently on nobody's list.

---

## Standing constraints

These were each learned the expensive way. They are not preferences.

1. **No remote CLI schema commands.** No `supabase db push`, `supabase migration up`, or
   `--linked` schema operations against either Vamo database. SQL-editor promotion of one
   reviewed migration at a time. See `operations/MIGRATION_PROMOTION_POLICY.md`.
2. **The migration ledger is unusable.** `supabase_migrations.schema_migrations` has no
   rows in either database despite migrations being structurally present. Applied state is
   established by object probe until MW0 completes.
3. **Never invoke `trip-lifecycle-jobs` manually in Production.** It sends close notices,
   seven-day reminders, soft-close transitions and push. Deploy and wait for 06:00 UTC.
4. **Never create or rotate `CRON_SECRET` in Production.** It exists and the live cron
   authenticates with it; recreating it silently 401s the daily job.
5. **Staging cannot validate Production by resemblance.** Default privileges differ between
   the two projects. Assert an absolute target state in both, never a delta.
6. **Every product write must be a declared, checksummed inbox item.** No triggers or
   after-apply extensions that write product rows outside `confluendo_inbox.shipment_items`.
7. **Source-text tests prove text, not behaviour.** A green migration-string test has twice
   passed while an invariant was silently dropped. Behavioural assertions belong in
   `supabase/tests/`, which runs against PostgreSQL 16 in CI with a database per harness.
8. **Production smokes that write money data** use a dedicated smoke trip with controlled
   accounts, never a real shared trip, with the cleanup path proven in Staging first.

---

## Slice prompts

`docs/slices/` holds 43 slice prompts and is the working spec store — scope, acceptance and
files, per slice. Three naming generations coexist: numbered (`S17`–`S51`), letter-prefixed
matching the cycle specs (`M_P0_SUBTRIPS`, `D_P1_A_POI_DISCOVERY`, `H_WEATHER_PREVIEW`), and
descriptive (`TRIP_MAP_P0`, `POI_PLACE_INFO`, `PLAN_ADD_REDESIGN`).

**Known gap:** `slices/README.md` indexes only `S15`–`S46`. Roughly ten prompts — including
`TRIP_MAP_P0`, `S51_VISIT_POI`, `M_P0_SUBTRIPS` and `PLACE_DATA_RIGHTS_ENFORCEMENT` — appear
in no index at all. Anyone looking for the current spec of a feature has to list the
directory. Worth one small pass to index them.

---

## Where the detail lives

| Topic | Document |
| --- | --- |
| Place-data rights model and acquisition funnel | `architecture/DATA_ACQUISITION_STRATEGY.md` |
| Place-data enforcement contract | `slices/PLACE_DATA_RIGHTS_ENFORCEMENT_PROMPT.md` |
| Migration promotion policy | `operations/MIGRATION_PROMOTION_POLICY.md` |
| Consumer identity / environment marker | `operations/CONFLUENDO_CONSUMER_IDENTITY_PROMOTION.md` |
| Privilege convergence | `operations/FUNCTION_PRIVILEGE_CONVERGENCE_PROMOTION.md` |
| Custom expense split | `operations/CUSTOM_EXPENSE_SPLIT_PROMOTION.md` |
| Scheduled jobs and heartbeats | `SCHEDULED_JOBS.md` |
| Wave 2 history (closed) | `slices/README.md` |
| Closed-beta gates | `operations/LAUNCH_GATES.md` |
| 14-day beta scorecard | `operations/BETA_SCORECARD.md` |
| Information architecture + wave retag decision | `design/NAVIGATION_MAP.md` |
| Subtrips / "Follow me" spec | `specs/cycle5-subtrips-followme.md` |
| Product direction, waves and gates | `business/Vamo_Roadmap.docx` |
