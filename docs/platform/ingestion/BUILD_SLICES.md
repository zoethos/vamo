# Ingestion Platform Build Slices

Status: implementation slicing record - updated 2026-07-06.

This plan turns `docs/platform/ingestion/ARCHITECTURE.md` into
buildable slices. The platform is incubated in this repo, but it must stay
portable. Vamo is customer zero, not the platform boundary.

## Build Principles

- Build a reusable ingestion platform, not a Vamo scraper.
- Keep platform packages independent from Flutter, Vamo feature packages, and
  Vamo product tables.
- Start with no-network fixtures and dry-run shipment before real providers or
  production writes.
- Make policy executable: source rights, retention, attribution, media storage,
  and live-only rules are gates, not notes.
- Treat Postgres and Supabase/Postgres as first target adapters, not the whole
  abstraction.
- Keep production target writes disabled until auth, control API, leases, audit
  logs, target guards, CI smokes, and operator approvals exist.

## Product Goal: Governed Autonomy

The end-state is not an operator watching and approving every wave. Confluendo's
target workflow is:

1. Operator approves data sources, consumer target, geography/category coverage,
   and policy bounds.
2. Confluendo plans deterministic batch work.
3. Confluendo executes dry-runs, staging canaries, and production-inbox packages
   autonomously inside those bounds.
4. Confluendo stops and asks for operator review only when a guard trips, a new
   blocker appears, drift is detected, or the policy must widen.

Manual one-unit waves are **commissioning evidence**, not the steady-state
product. See `AUTONOMOUS_BATCH_ORCHESTRATION.md` for the autonomy contract and
stop conditions.

## Incubation Layout

Use the existing TypeScript workspace because it is already isolated from the
Dart/Melos app and can be lifted into a standalone repo later.

```text
web/
  packages/
    ingestion-platform/
      README.md
      spec/
      core/
      policy/
      adapters/
        source/
        target/
        transform/
      fixtures/
  apps/
    site/                         # Vamo web/admin shell; consumer UI only
```

Only create a new app or service when a slice needs it:

```text
web/apps/ingestion-control-api/    # later, when mutation boundary exists
tool/ingestion/                    # optional local CLI/dev harness
```

Vamo-specific profiles are consumer-owned and imported, not authored inside core
packages (see IP-03.5). The consumer publishes the contract in its own repo; the
platform keeps a pinned snapshot:

```text
Z:\vamo/contracts/ingestion/vamo-place-intelligence/            # consumer-owned source of truth
web/packages/ingestion-platform/fixtures/imported/vamo-place-intelligence/   # pinned snapshot
```

## Slice IP-00 - Strategy And Visual Shell

Status: done.

Already landed:

- Static `/admin/ingestion` mockup.
- Reusable ingestion platform architecture.
- Embeddable product/market wedge.

No live controls, no target writes, no source access.

## Slice IP-01 - Spec Kernel And Fixture Contract

Goal: define and validate the YAML contract before any database or worker code.

Architecture decision: platform namespace boundary. Put strict schema parsing
and normalization in `web/packages/ingestion-platform/spec`; keep it pure and
portable.

Files:

- `web/packages/ingestion-platform/package.json`
- `web/packages/ingestion-platform/spec/src/index.ts`
- `web/packages/ingestion-platform/spec/src/pipeline.ts`
- `web/packages/ingestion-platform/spec/src/target.ts`
- `web/packages/ingestion-platform/spec/src/validation.ts`
- `web/packages/ingestion-platform/spec/test/*.test.ts`
- `web/packages/ingestion-platform/fixtures/examples/vamo-place-intelligence/*.yaml`

Behavior:

- Parse pipeline YAML.
- Parse target-project YAML.
- Validate required fields.
- Validate adapter names against an allowlist.
- Validate source license/policy flags.
- Validate target security requirements.
- Emit normalized JSON usable by the admin mockup.

Acceptance criteria:

- Invalid YAML fails with structured errors and field paths.
- A valid Vamo place-intelligence fixture passes.
- Unknown source/target adapter names fail.
- A target spec with Supabase service-role exposure to browser fails.
- A source that requests media-byte storage without policy permission fails.
- No network calls.
- No database calls.

Tests:

- Valid fixture parse.
- Missing required source fields.
- Unknown adapter.
- Policy contradiction.
- Target security guard.

Definition of done:

- `npm --workspace @confluendo/ingestion-platform test -- spec` passes.
- `npm --workspace @confluendo/ingestion-platform build` passes.
- Static admin mock data can optionally import generated fixture JSON.

## Slice IP-02 - Platform Control Schema Draft

Status: done.

Goal: model the platform-control database without tying it to Vamo product
tables.

Architecture decision: SQL/schema artifact first. Keep it in a platform path and
do not push it to Vamo staging until reviewed.

Files:

- `web/packages/ingestion-platform/core/sql/control_schema.sql`
- `web/packages/ingestion-platform/core/src/control-models.ts`
- `web/packages/ingestion-platform/core/test/control-schema.test.ts`

Tables:

- `ingestion_projects`
- `ingestion_specs`
- `ingestion_sources`
- `ingestion_targets`
- `ingestion_runs`
- `ingestion_tasks`
- `ingestion_worker_leases`
- `ingestion_checkpoints`
- `ingestion_events`
- `ingestion_dead_letters`
- `ingestion_artifacts`
- `ingestion_policy_evaluations`
- `ingestion_promotions`
- `ingestion_shipments`
- `ingestion_shipment_items`
- `ingestion_audit_log`

Acceptance criteria:

- Schema creates in a disposable local Postgres database.
- Tables use platform names only.
- Audit/event/checkpoint tables are append-friendly.
- Checkpoints are unique per pipeline/source/target cursor scope.
- Shipment items have idempotency keys.
- No Vamo product table names are required by the platform schema.

Tests:

- Apply schema to temporary Postgres.
- Insert a pipeline spec revision.
- Create run/task/checkpoint/event rows.
- Enforce unique checkpoint scope.
- Enforce shipment idempotency key uniqueness.

Definition of done:

- Local schema smoke passes.
- No Supabase cloud push.
- No Vamo production/staging mutation.

## Slice IP-03 - Fixture Source Adapter And Policy Engine

Status: done.

Goal: run a no-network ingestion pass from fixture data into staging candidates.

Architecture decision: adapter/gateway. Source access goes through source
adapter interfaces; policy evaluation is a separate pure module.

Files:

- `web/packages/ingestion-platform/core/src/pipeline-runner.ts`
- `web/packages/ingestion-platform/policy/src/index.ts`
- `web/packages/ingestion-platform/adapters/source/src/fixture-source.ts`
- `web/packages/ingestion-platform/fixtures/examples/vamo-place-intelligence/source.jsonl`
- tests across the three packages

Behavior:

- Read bounded fixture batches.
- Apply mapping/transforms from spec.
- Evaluate policy gates.
- Produce staged candidate records and events.
- Produce dead letters for invalid rows.
- Commit in-memory or local Postgres checkpoints.

Acceptance criteria:

- A fixture run produces candidates, policy evaluations, events, and checkpoint
  output.
- Invalid rows go to dead letter with classified reason.
- Policy-blocked rows do not become candidates.
- Checkpoint resumes from the next row.
- No external network calls.

Tests:

- Batch checkpointing.
- Resume from checkpoint.
- Policy allow/deny.
- Dead-letter classification.
- Transform output determinism.

## Slice IP-03.5 - Consumer Contract Export/Import

Status: done.

Goal: make consumers own their requirements. A consumer (Vamo first) publishes a
YAML contract bundle in its own repo; the platform imports a pinned snapshot and
runs against that copy. The platform must not read a consumer repo at runtime.

Architecture decision: consumer boundary by import, not by reference. Vamo is
customer zero, so its profile stops being a platform-authored example and becomes
an imported artifact with recorded provenance.

Files:

- `Z:\vamo/contracts/ingestion/vamo-place-intelligence/` (consumer repo): `manifest.yaml`,
  `pipeline.yaml`, `target.yaml`, `fixtures/source.jsonl`.
- `web/packages/ingestion-platform/spec/src/consumer-contract.ts` - manifest parser.
- `web/packages/ingestion-platform/scripts/import-consumer-contract.mjs` - snapshot importer.
- `web/packages/ingestion-platform/fixtures/imported/vamo-place-intelligence/` - generated snapshot.
- `web/packages/ingestion-platform/fixtures/platform/` - platform-owned test fixtures.
- tests: `spec/test/consumer-contract.test.ts`, `core/test/consumer-contract-import.test.ts`.

Behavior:

- Validate a consumer `manifest.yaml` (kind, consumer, profile, version, exports)
  with the spec kernel, rejecting export paths that escape the bundle.
- Copy a snapshot into `fixtures/imported/<consumer>-<profile>/`.
- Re-validate the imported pipeline/target with the IP-01 kernel.
- Record provenance: source repo, commit SHA, per-file content hashes, in
  `IMPORT_METADATA.json`.

Acceptance criteria:

- The platform never reads the consumer repo at runtime; tests run against the
  committed snapshot.
- Import fails if the manifest, pipeline, or target is invalid.
- Snapshot carries source commit SHA and content hashes.
- The imported Vamo profile parses (IP-01) and dry-runs (IP-03).

Definition of done:

- `npm --workspace @confluendo/ingestion-platform run import:contract -- --from <dir>` regenerates the snapshot.
- `npm --workspace @confluendo/ingestion-platform test` passes.

## Slice IP-04 - Postgres Dry-Run Target Adapter

Status: done.

Goal: compare promoted candidate records against a target schema without writing.

Architecture decision: target adapter. Postgres is the first adapter, but core
shipment stays target-neutral.

Files:

- `web/packages/ingestion-platform/adapters/target/src/postgres-dry-run.ts`
- `web/packages/ingestion-platform/core/src/shipment-plan.ts`
- `web/packages/ingestion-platform/core/src/diff.ts`
- tests with local Postgres fixtures

Behavior:

- Connect to a target Postgres database using a server-side DSN.
- Inspect configured target tables and required columns.
- Build insert/update/no-op/delete diff.
- Validate upsert keys.
- Emit shipment plan, checksums, and incompatibility errors.
- Write nothing.

Acceptance criteria:

- Valid target schema produces a dry-run shipment diff.
- Missing table/column fails before any write.
- Upsert key mismatch fails.
- Re-running dry-run is deterministic.
- Target credentials never enter browser code.

Tests:

- Empty target diff.
- Existing row no-op.
- Existing row update.
- Missing table.
- Missing upsert key.

## Slice IP-05 - Supabase/Postgres Target Adapter

Status: done.

Goal: add Supabase-specific target rules while still using the Postgres shipment
contract.

Architecture decision: adapter extension. Supabase is a target engine profile
with extra security checks, not a separate core path.

Files:

- `web/packages/ingestion-platform/adapters/target/src/supabase-postgres.ts`
- `web/packages/ingestion-platform/adapters/target/src/supabase-security-checks.ts`
- tests with local or sandbox Supabase/Postgres where available

Behavior:

- Verify exposed-schema tables have RLS when configured.
- Verify Data API grants are explicit where the target spec requires them.
- Forbid service-role/browser exposure in specs.
- Use server-side DSN or trusted service boundary.
- Keep production writes disabled until later approval flow exists.

Acceptance criteria:

- Supabase target specs with browser service-role exposure fail validation.
- Exposed public tables without RLS fail validation when required.
- Dry-run works against a Supabase/Postgres target shape.
- No production writes.

Tests:

- Security guard failures.
- Schema compatibility pass/fail.
- Dry-run plan generation.

## Slice IP-06 - Local Control API And Admin Read Model

Status: done. Read model + wiring are implemented, and browser visual QA passed
at desktop and mobile breakpoints after a clean local dev-server restart.

Goal: expose read-only run/target/event/status data to the admin page from the
platform model instead of hand-written static content.

Architecture decision: service boundary. Admin UI reads through an API/read
model; it does not read/write control tables directly. The read model is a pure
transform exposed on its own package subpath (`@confluendo/ingestion-platform/read-model`)
so the Next bundle never pulls `pg`/`node:fs` and there is no control-table or
service-role access in browser-reachable code. A live control API can later feed
the same transform real rows; only the snapshot source changes.

Files:

- `web/apps/confluendo-console/app/admin/ingestion/page.tsx` (unchanged shell; label only)
- `web/apps/site/content/ingestion-dashboard.ts` (now reads through the read model)
- `web/packages/ingestion-platform/core/src/read-model.ts` (transform + view/domain
  types + sample control-plane snapshot)
- `web/packages/ingestion-platform/core/test/read-model.test.ts`
- `@confluendo/ingestion-platform` added as a `@vamo/site` workspace dependency
- optional `web/apps/ingestion-control-api/` (deferred — no live API yet)

Behavior:

- Generate dashboard cards from fixture/control-plane read model.
- Keep all mutation controls disabled.
- Surface targets, events, checkpoints, worker leases, and stats from a common
  shape.

Acceptance criteria:

- Browser QA shows the same visual shell populated from platform read-model
  data.
- No service-role secrets in Next public code.
- No mutation endpoint exists yet.
- Desktop/mobile responsive checks remain clean.

Tests:

- Read model transforms runs/tasks/events into dashboard state.
- Admin page renders expected labels.
- Browser smoke at desktop and mobile.

## Slice IP-07 - Worker Leases And Command Semantics

Status: done.

Goal: implement start/pause/shutdown/reset semantics against local tasks and
leases before real external ingestion.

Architecture decision: pure policy plus command adapter. State transitions are
pure and tested; persistence is adapter-backed.

Files:

- `web/packages/ingestion-platform/core/src/commands.ts`
- `web/packages/ingestion-platform/core/src/leases.ts`
- `web/packages/ingestion-platform/core/src/run-state.ts`
- tests

Behavior:

- Start creates/activates eligible tasks.
- Pause drains safely and preserves checkpoint.
- Shutdown releases worker after checkpoint flush.
- Reset only affects failed/blocked leases and requires an audit reason.
- Target-level control works independently of cluster-level control.

Acceptance criteria:

- Invalid transitions fail with structured errors.
- Pause never deletes checkpoint state.
- Reset cannot run without audit reason.
- Target pause does not pause unrelated targets.
- All command attempts emit audit events.

Deferred before admin mutation controls: document the `ok` flag contract for
idempotent no-ops and partial-success plans, including whether "already in the
desired state" should surface as success with skipped metadata.

Tests:

- Run-state transition matrix.
- Lease heartbeat timeout.
- Target-level pause.
- Reset blocked without reason.
- Audit event emission.

## Slice IP-08 - Containerized Worker Harness

Status: done.

Goal: run the fixture pipeline through a containerized worker locally.

Architecture decision: runtime wrapper. Worker process wraps the already-tested
core; it should add no hidden product logic.

Files:

- `tool/ingestion/docker-compose.yml`
- `tool/ingestion/worker.Dockerfile`
- `web/packages/ingestion-platform/core/src/worker-main.ts`
- scripts in `web/package.json`

Behavior:

- Worker starts, claims a fixture task, processes batches, emits checkpoints and
  events, and exits cleanly on pause/shutdown.
- Can be restarted and resumes from checkpoint.

Acceptance criteria:

- `docker compose up` runs a fixture ingestion locally.
- Killing worker mid-run resumes from last committed checkpoint.
- Events show failure/restart reason.
- No external provider calls.

Tests/smokes:

- Local Docker smoke.
- Kill/restart smoke.
- Checkpoint assertions.

## Slice IP-09 - Vamo Place Intelligence Consumer Profile

Status: done.

Goal: add the first real consumer profile while keeping it outside platform
core.

Architecture decision: consumer adapter/profile. Vamo mappings and product table
names live in profile/spec files, not core packages.

Files:

- `Z:\vamo/contracts/ingestion/vamo-place-intelligence/*.yaml` (consumer-owned; imported via IP-03.5)
- `web/packages/ingestion-platform/fixtures/imported/vamo-place-intelligence/` (pinned snapshot)
- `docs/platform/ingestion/ARCHITECTURE.md` updates if needed
- optional Vamo target schema compatibility fixtures

Behavior:

- Map source candidate fields into Vamo place-intelligence target tables.
- Express required target keys that are not direct source fields, including the
  provider `source` constant and a deterministic `canonical_key` derivation.
- Dry-run against a Postgres schema fixture that mirrors the Vamo
  `place_intelligence_cache` tables, including numeric latitude/longitude
  columns.
- Validate PII firewall rules.
- Validate Google live-only policy.
- Produce a dry-run shipment diff for Vamo staging shape.

Acceptance criteria:

- Vamo profile can be validated by IP-01 spec parser.
- Vamo profile can run through fixture source adapter.
- Vamo profile produces a Postgres/Supabase dry-run plan.
- Existing Vamo numeric/timestamp values compare as no-ops when semantically
  equal to candidate values.
- The imported Vamo contract fixture catches missing computed/constant upsert
  keys before shipment.
- No cloud staging write until explicit green light.

## Slice IP-10 - First Real Open Dataset Source

Status: done.

Goal: introduce the first real, policy-safe source after the spine is proven.

Recommended first source: a small public/open dataset subset or manually
downloaded fixture snapshot, not a live provider API.

Architecture decision: source adapter. Real source code still flows through the
same fixture-proven adapter interface and policy engine.

Behavior:

- Load a bounded snapshot.
- Validate license/attribution fields.
- Process in batches.
- Produce dry-run shipment only.

Acceptance criteria:

- No rotating VPN/proxy behavior.
- Source license metadata is required.
- Attribution rows are produced.
- Policy blocks are visible in telemetry.
- Shipment remains dry-run until review.

## Slice IP-10.1 - Real EU POI Snapshot Supply

Status: **done** — merged in PR #133 (`b066e3b7`).
Source-supply descendant of IP-10; sequenced **before the next live IP-18.5
wave / IP-18.6 production wave** so orchestration operates on real candidates
instead of the 5-row demo fixture.

Source of truth: `docs/platform/ingestion/IP_10_1_SOURCE_EXPANSION_PROMPT.md`.

Why: IP-18 batch planning expands `vamo-eu-poi-batch.yaml` into 36 geo/category
units, but the imported candidate supply is only 5 rows, all `category: poi`, 3
cities. Downstream dry-run/wave slices are validating clean machinery against a
starved queue. This slice feeds real, bounded, open/cacheable candidate supply.
It is **not** an IP-18 batch-orchestration phase; **IP-18.6 stays reserved for
production-inbox waves.**

Scope:

- Replace/extend the 5-row demo fixture with a bounded real EU POI snapshot
  (FSQ OS Places), open/cacheable only — local snapshot, no URL/proxy/VPN, no
  Google, `canStoreMediaBytes: false`.
- Every source row carries `scope.geography` and `scope.category` matching the
  batch-plan keys.
- Fix the mapping so `feature_type` derives from `scope.category` (allowlist
  `{poi,landmark,restaurant,transport}`), not the hardcoded `value: poi`.
- Switch the contract source adapter `fixture` → `snapshot` and regenerate the
  pinned consumer contract via `import:contract`.
- Re-run IP-18 batch planning/seed and local candidate-coverage checks against
  real candidate supply.

Guardrails: no Vamo staging or production writes (ends at dry-run with real
candidates); IP-16 adapter stays the only staging write boundary;
`ip15:boundary-audit` output unchanged; do not hand-edit the pinned imported
bundle.

Acceptance criteria:

- Batch dry-run reports candidates > 0 for the 9-geography × 4-category coverage
  set, with `feature_type` matching the unit category (not all `poi`).
- `wroteToTarget=false` on every unit; no live provider, staging, or production
  writes.
- `import:contract` regenerates `IMPORT_METADATA.json` with `adapter: snapshot`
  and the new fixture sha256.
- Spec tests + `ip15:boundary-audit` green; `git diff --check` clean.

Implementation evidence:

- Contract source now uses `adapter: snapshot`, `snapshotPath:
  fixtures/source.jsonl`, and contract version 4.
- Bounded local snapshot contains **38 rows**: 36 valid staged candidates covering
  all 36 IP-18 geography/category units, plus one missing-name dead-letter row
  and one media-byte policy-block row.
- `feature_type` derives from `scope.category` and the spec/policy layer enforces
  an `allowed_values` gate for `poi`, `landmark`, `restaurant`, and `transport`.
- Local no-DB coverage probe: **36 candidates / 36 planned units / 0 missing
  units**, with 2 dead letters and 1 policy block.
- Review validation for PR #133: ingestion-platform tests **218 pass / 13
  skipped / 0 failed**, `ip15:boundary-audit` passed, `ip18:batch-plan`
  returned **36 planned / 0 blocked**, and fixture checksums were regenerated.

## Slice IP-11 - Authenticated Live Control Mutation API

Status: done.

Goal: turn the operator controls from a read-only shell into authenticated,
audited control-plane mutations while preserving the no-production-write guard.

Architecture decision: server-side API boundary plus pure command policy. The
browser posts commands to a Next route; the route resolves the authenticated
admin principal and calls the platform control API. The platform package owns
state planning and SQL mutation logic; UI code never writes control tables
directly.

Implemented:

- `web/apps/confluendo-console/app/api/admin/ingestion/commands/route.ts`
- `web/apps/confluendo-console/app/admin/ingestion/ingestion-command-controls.tsx`
- `web/apps/confluendo-console/lib/ingestion-admin-auth.ts`
- `web/packages/ingestion-platform/core/src/control-command-api.ts`
- `web/packages/ingestion-platform/core/src/admin-auth.ts`
- command planner, idempotent no-op, partial-success, stale-patch, audit, and
  machine-token tests.

Behavior:

- Session-authenticated admins can issue `start`, `pause`, `shutdown`, and
  `reset` through the command API when role, scope, MFA, and fresh-step-up rules
  allow it.
- A machine token can run only non-destructive operational commands; destructive
  commands require an MFA-gated admin session.
- Every accepted, rejected, partial, stale, and no-op command writes an audit
  record.
- Commands mutate only control-plane tasks and leases. They do not ship rows to
  consumer production databases.

Acceptance criteria:

- Browser code has no database credentials or service-role secrets.
- Admin identity is derived from Supabase session plus the platform allowlist,
  not from caller-supplied request fields.
- `reset` requires a reason and a fresh MFA step-up.
- The `ok` contract is explicit: idempotent no-ops are accepted, partial
  success applies valid patches and reports warnings, and stale patches fail the
  apply result.
- Audit payload records applied, stale, skipped, and rejected work.

Validation:

- `npm --workspace @confluendo/ingestion-platform test`
- `npm --workspace @confluendo/console run build`

## Slice IP-12 - Target Selection And Progressive Scheduling

Status: spec documented.

Goal: define how Confluendo chooses ingestion targets and how AI can assist
progressive scheduling without becoming an uncontrolled source of truth.

Architecture decision: pure planning policy plus adapter-backed execution.
Target scoring and scheduling rules belong in platform core as pure, testable
policy. Source reads, target writes, AI calls, and dashboard mutations remain
adapter/API boundaries.

Source of truth:

- `docs/platform/ingestion/TARGET_SELECTION_AND_SCHEDULING.md`

Selection criteria:

- Consumer value.
- Source rights, retention, and attribution.
- Target DB readiness, schema compatibility, RLS, grants, and upsert keys.
- Data quality and collision risk.
- Checkpointability and replayability.
- Cost, quota, runtime, and stop conditions.
- Dashboard observability.

AI role:

- AI can rank targets, propose source partitions, estimate schedules, summarize
  dry-run diffs, classify dead letters, and explain why a target should run.
- AI cannot bypass policy, source terms, operator approval, MFA, target schema
  review, or production shipment gates.

Dashboard requirement:

- The operator console must show proposed, scheduled, running, blocked, and
  completed work; AI rationale; checkpoints; quota; policy blocks; dead
  letters; collision risk; shipment diffs; and the exact approval needed to
  move to the next tier.

## Slice IP-13 - DB-Backed CI Smoke For Control SQL

Status: done.

Goal: make the SQL-backed control-plane read/write path run in CI against a
real Postgres service instead of relying only on mock clients.

Architecture decision: CI safety net, not product logic. The existing
`INGESTION_TEST_DATABASE_URL` smoke remains in the platform test suite; GitHub
Actions supplies a disposable Postgres service so the smoke is no longer skipped
in pull requests.

Acceptance criteria:

- CI starts a disposable Postgres service.
- `npm --workspace @confluendo/ingestion-platform test` runs with
  `INGESTION_TEST_DATABASE_URL`.
- The control schema creates, uniqueness constraints hold, and real
  start/shutdown/reset command mutations apply against SQL.
- No external providers or consumer staging/production databases are contacted.

## Slice IP-14 - First Vamo Progressive Dry Run

Status: done. Merged to `main` via PR #95 with CI green (build/test, DB-backed
control smoke, secret and dependency scans).

Goal: a bounded, observable, dry-run-only Vamo ingestion selected through the
target scorecard and visible in the dashboard, with production and staging
writes impossible.

Architecture decision: pure policy in platform core, Vamo as a consumer.
Scorecard, schedule proposal, progressive run orchestration, and the dashboard
read model are pure, dependency-free modules. Vamo specifics enter only as
declarative fixtures and injected adapters. The live control read is the
platform-owned, consumer-generic half (reads `ingestion_platform.*` only). No
Vamo runtime coupling lives in core.

Implemented components:

- Target scorecard policy (`core/src/target-scorecard.ts`): deterministic
  weighted scoring across nine hard gates.
- Schedule proposal policy (`core/src/schedule-proposal.ts`): bounded proposal
  with scope, batch size, checkpoint interval, quota budget, stop conditions,
  safety mode, advisory AI rationale (deterministic, no live LLM), and the
  required approval. `production_write`/`staging_write` are rejected for this
  slice.
- Progressive run orchestration (`core/src/progressive-run.ts`): `preflight`,
  `scout`, `sample_dry_run`, and `review_required` stages; it only reaches
  `review_required` when preflight passes and the shipment diff is compatible,
  otherwise it stays blocked at `sample_dry_run` with a resolve-blockers
  approval.
- Dashboard read model (`core/src/progressive-read-model.ts`): browser-safe
  transform surfacing work status, score, AI advisory, tier, stage, checkpoint,
  row counts, policy blocks, dead letters, blockers, shipment diff, the
  `wroteToTarget` dry-run invariant, and the exact next approval.
- CLI harness (`scripts/run-ip14-dry-run.mjs`, `ip14:dry-run`): runs the dry run
  end-to-end against bundled fixtures, prints a readable summary, hard-fails on
  any non-`dry_run` safety mode, needs no secrets, and exits non-zero when the
  run is blocked or incomplete.
- Live control read (`core/src/progressive-control-read.ts`) and the dashboard
  section: the admin console renders real/proposed progressive work from the
  control plane when present, and falls back to the bundled sample otherwise.

Durable schema addition:

- `ingestion_platform.ingestion_schedule_proposals` (registered in
  `CONTROL_TABLES`, now 18). One row per target candidate/proposal, storing the
  deterministic scorecard, the bounded proposal, and the latest progressive-run
  report as JSONB, plus a `(project_id, work_status, created_at)` index. This is
  a read surface; no scheduling-mutation path writes it yet.

Dry-run-only guardrails:

- `safety_mode` is `dry_run`; `staging_write` and `production_write` are
  rejected by proposal policy and the harness hard-fails on anything else.
- No real provider scraping, no VPN/proxy/evasion, no live AI calls.
- No production or staging writes; `wroteToTarget` is always false.
- No service-role secrets in browser code; the live read is server-only.
- No direct Vamo product coupling in platform core.

Operator approval required before any staging canary:

- Promotion out of `review_required` requires an `ingestion_admin` principal
  with an MFA step-up and an audit reason, plus an explicit promotion from
  `review_required` to `staging_write`. That promotion path is intentionally not
  built in this slice; it is deferred to a future staging-canary slice.

Validation (local, all green):

- `npm --workspace @confluendo/ingestion-platform test` - 114 pass, 2 DB smokes
  skipped without a database URL, 0 fail.
- `npm --workspace @confluendo/ingestion-platform run ip14:dry-run` - exit 0,
  `dry_run`, no writes.
- `npm --workspace @confluendo/console run build` - succeeds; `/admin/ingestion` renders.
- Disposable Postgres with `INGESTION_TEST_DATABASE_URL` - core suite 86/86,
  including the `ingestion_schedule_proposals` round-trip and the 18-table
  schema smoke. The spec test runner now uses `--test-concurrency=1` so DB
  smokes that recreate the shared disposable schema cannot deadlock.

Remaining follow-ups:

- Optionally produce a real `ingestion_schedule_proposals` row in the control DB
  so the dashboard shows live progressive work instead of the sample.
- Add a scheduling mutation endpoint (operator-driven proposal/schedule writes).
- Add the staging-canary slice that implements the `review_required` ->
  `staging_write` promotion with the approval gate above.
- Prepare the Confluendo repo split (IP-15 below), now that IP-14 has landed.

## Slice IP-15 - Confluendo Repo Split Prep

Status: active prep. Package namespace, executable audit checks, and the
in-repo Confluendo console carve-out are in progress; this is not the physical
repo move.

Goal: prepare Confluendo to leave the Vamo incubation tree as an independent
repo, while making Vamo an importing consumer instead of the platform host.

IP-14 through IP-17 have landed and prove the current spine:

```text
Vamo contract -> Confluendo import -> dry-run -> staging canary
  -> production inbox package -> Vamo-owned apply
```

The 2-row production inbox delivery proved the pipe; it did not solve the real
product need of broad EU POI ingestion. Before IP-18 batch automation, keep
Confluendo from becoming Vamo-shaped.

Architecture decision: provider repo plus consumer contracts. Confluendo owns
platform code, docs, auth templates, control SQL, worker runtime, adapters, and
admin surfaces. Vamo owns only its consumer contract, target credentials, product
schema, and integration notes.

Source of truth:

- `docs/platform/ingestion/CONFLUENDO_EXTRACTION_PREP.md`

Allowed dependency direction:

- Vamo may depend on Confluendo packages, CLI, hosted APIs, embedded admin UI,
  and contract schemas.
- Confluendo must not depend on Vamo app code, Flutter packages, Vamo web
  routes, Vamo Supabase edge functions, or Vamo migrations.
- Confluendo may carry Vamo only as an example/imported consumer fixture with
  pinned provenance.

Implemented in this prep slice:

- Package identity and imports move from `@vamo/ingestion-platform` to
  `@confluendo/ingestion-platform`.
- `@confluendo/console` owns the operator console under
  `web/apps/confluendo-console`.
- `@vamo/site` no longer imports Confluendo packages; `/admin/*` is a handoff to
  the console boundary.
- `ip15:boundary-audit` verifies the package namespace, stale import absence,
  console ownership, site non-dependency, and no direct platform runtime imports
  from host/Vamo paths.
- Extraction-prep docs define current incubation tree, target standalone tree,
  ownership matrix, lift sequence, and gates before IP-18.

Deferred to physical extraction:

- Move `web/packages/ingestion-platform` into a standalone Confluendo repo.
- Move `web/apps/confluendo-console` to the standalone Confluendo repo and wire
  `confluendo.com`/Vercel to that app.
- Move Vamo-specific imported fixtures into `examples/consumers/` or an explicit
  test fixture namespace in the standalone repo.
- Convert `control_bootstrap_confluendo.sql` into a platform bootstrap template
  plus customer examples.
- Replace remaining Vamo default project keys in the Vamo host with environment
  or project configuration where they are not intentionally customer-zero.

Acceptance criteria:

- A clean dependency scan shows no platform imports from Vamo runtime modules.
- The platform package, docs, and SQL are branded Confluendo, not Vamo.
- Vamo's contract bundle remains consumer-owned and can be imported into the
  platform from outside the platform repo.
- Vamo can still run its customer-zero dashboard/integration against the
  extracted Confluendo package/API.
- The new repo can run the ingestion-platform test suite with disposable
  Postgres.

Validation:

- `npm --workspace @confluendo/ingestion-platform run ip15:boundary-audit`
- `npm --workspace @confluendo/ingestion-platform test`
- `npm --workspace @confluendo/console run build`
- `npm --workspace @vamo/site run build`

## Slice IP-16 - First Vamo Staging Canary

Status: done, merged to `main` in the Confluendo/web dashboard repo via PR #97
and hardened by PR #99 and PR #101 (PR #101 corrected the reviewed canary scope
to rome-italy/poi — 1 candidate, 2 writes — and added a fresh-MFA countdown in
the admin mastheads). The Vamo app schema migration
`20260625155733_place_intelligence_cache.sql` has also been promoted to Vamo
staging and production under `docs/operations/MIGRATION_PROMOTION_POLICY.md`.
The actual live write into Vamo staging remains manual and separately approved:
it requires an explicit `CONFIRM_VAMO_STAGING_CANARY=YES` confirmation, a fresh
dashboard approval, a staging DSN, and `--execute`. CI/tests never need live
Vamo staging credentials.

Goal: promote exactly one reviewed dry run (a target at `review_required` with a
compatible diff and `wroteToTarget === false`) to a tiny, bounded, reversible
write into Vamo staging only. This is Confluendo's first write to a consumer
database; production shipment remains blocked by policy, durable write modes,
and a positive staging proof at the adapter.

Architecture decision: pure approval/shipment policy in platform core; target
writes happen only through the `adapters/target` boundary; Vamo remains a
consumer profile/config, never a platform dependency. Promotion gate, bounds
enforcement, staging-only decision, ledger/idempotency planning, rollback
planning, and the canary state machine are pure and DB-free. The only code that
writes to Vamo staging is the target adapter, which first proves a staging
connection.

Source of truth:

- `docs/platform/ingestion/STAGING_CANARY.md`

Defines:

- Goal: promote one reviewed dry run to a tiny Vamo staging write.
- Source: open/cacheable snapshot only (no live scraping, no VPN/proxy/evasion).
- Target: Vamo staging only, resolved from consumer config.
- Hard production block at three layers: policy rejects `production_write`,
  durable target/shipment write modes only allow `dry_run`/`approved_write`, and
  the adapter refuses unless the target DB exposes the DBA-provisioned sentinel
  row `confluendo_guard.environment_sentinel` with `key='environment'` and
  `value='staging'`.
- Approval requirement: `ingestion_admin` + fresh MFA step-up + audit reason +
  explicit `review_required -> staging_write` transition; machine tokens cannot
  promote.
- Canary bound: small row count (recommended `<= 50`), one geography, one
  category, idempotent upsert on declared keys, no `delete`, single shipment.
- Rollback: every written row is traceable by `shipment_id`/`run_id`; inserts
  are removable and updates are reversible via captured prior state; one audited
  operator action; idempotent.
- Telemetry: approval audit, shipment ledger (`ingestion_shipments`/`_items`),
  checkpoint, dead letters, policy blocks, attribution, events, and audit log.
- Operator dashboard state transitions: `review_required ->
  staging_canary_pending -> staging_canary_shipped | staging_canary_blocked`,
  with `staging_canary_rolled_back`; no production node.
- Explicit stop conditions that always leave a no-write or fully-rolled-back
  state.
- Safety-mode mapping: policy `staging_write` + environment `staging` maps to an
  `approved_write` shipment; `production_write` is rejected before durable
  target/shipment write.

Guardrails (carried from IP-14, unchanged):

- No production writes; no durable target/shipment write enum widening.
- No live provider scraping, no VPN/proxy/evasion, no live AI calls (AI stays
  advisory per `TARGET_SELECTION_AND_SCHEDULING.md` §3).
- No service-role secrets, DSNs, or write credentials in browser code.
- No Vamo runtime coupling in platform core.

Implementation phases:

1. **Docs/spec** (this section + `STAGING_CANARY.md`). Docs-only commit.
2. **Pure approval policy** (`core/src/staging-canary-policy.ts`): evaluate the
   `review_required -> staging_write` promotion. Inputs are the latest
   `ProgressiveRunReport`, the resolved approval context (role, MFA/AAL2
   freshness, audit reason), the requested transition, the canary bounds, and
   the resolved target environment. Output is a structured decision: either an
   accepted, bounded `StagingCanaryPlan` (shipment intent, idempotency keys,
   rollback plan) or ordered blocking reasons. Dependency-free and
   deterministic; no DB, no network, browser-safe.
3. **Shipment apply path** (`adapters/target/src/postgres-staging-canary.ts`):
   extend the proven dry-run planner with a transactional, idempotent
   apply/rollback. It first proves a staging connection by reading the target DB
   sentinel row `confluendo_guard.environment_sentinel` (`key='environment'`,
   `value='staging'`) plus the injected guard, then re-plans the diff, refuses
   to write if the diff drifted from review or the plan exceeds bounds or
   contains `delete`, applies bounded upserts in one transaction, captures prior
   row state for reversibility, and records shipment items. Tested against a
   fake `PgClientLike` and disposable Postgres (`INGESTION_TEST_DATABASE_URL`);
   live Vamo staging execution is manual and gated.
4. **Dashboard approval control**: a Next API route + client control that drives
   the gated promotion. The route resolves the authenticated admin principal and
   a fresh AAL2/MFA step-up (reusing IP-11 `ingestion-admin-auth`), requires a
   non-empty audit reason, derives the canary bounds from the reviewed
   control-plane proposal/report (not browser-entered scope/counts), calls the
   pure policy, and records the decision/audit. The browser never receives DSNs
   or write credentials, and the control plans the canary; it does not perform
   the live staging write itself.
5. **Live runbook + hard confirmation gate**
   (`scripts/run-ip16-staging-canary.mjs`, `docs/platform/ingestion/STAGING_CANARY_RUNBOOK.md`):
   a server-side CLI that runs the full gated path against a real staging DSN
   only when `CONFIRM_VAMO_STAGING_CANARY=YES`, a recorded dashboard approval
   audit id, the Confluendo control DB, a staging DSN/environment, and
   `--execute` are all present; the target DB must also expose
   `confluendo_guard.environment_sentinel` with `value='staging'`. Absent any
   gate it hard-fails and writes nothing. The runbook documents the manual,
   separately-approved live procedure and the rollback command.
6. **No live Vamo staging write** is executed in this slice. The live canary
   waits for an explicit operator green light.

Files (planned):

- `web/packages/ingestion-platform/core/src/staging-canary-policy.ts` + tests.
- `web/packages/ingestion-platform/adapters/target/src/postgres-staging-canary.ts`
  + tests (fake client + disposable Postgres).
- `web/packages/ingestion-platform/scripts/run-ip16-staging-canary.mjs` +
  `ip16:staging-canary` npm script.
- `web/apps/confluendo-console/app/api/admin/ingestion/staging-canary/route.ts` and a client
  approval control under `web/apps/confluendo-console/app/admin/ingestion/`.
- `docs/platform/ingestion/STAGING_CANARY_RUNBOOK.md`.

Acceptance criteria:

- The pure policy accepts a promotion only when the run reached review with a
  compatible diff and `wroteToTarget === false`, the principal is
  `ingestion_admin` with a fresh MFA/AAL2 step-up and a non-empty audit reason,
  the transition is explicitly `review_required -> staging_write`, the bounds
  hold (row count under the cap, one geography, one category, no `delete`,
  upsert keys present), and the resolved environment is `staging`. Every other
  case returns ordered blocking reasons and no plan.
- The adapter apply path writes only inside a transaction, is idempotent on
  re-run (no duplicate rows), captures prior state so updates are reversible,
  refuses to run unless the connection is proven staging, and rolls back fully
  on any failure or bound violation. Rollback removes inserts and reverts
  updates and is itself idempotent.
- `production_write` is rejected by policy before any durable target/shipment
  write; no production environment/DSN/adapter is added.
- The dashboard control cannot promote without admin + AAL2 + audit reason, and
  the browser bundle contains no DB credentials.
- Tests and CI pass without any live Vamo staging credentials; the live CLI
  hard-fails unless `CONFIRM_VAMO_STAGING_CANARY=YES`, a recorded approval id,
  the Confluendo control DB, staging DSN/environment, the target DB staging
  sentinel, and `--execute` are all present.

Validation:

- `npm --workspace @confluendo/ingestion-platform test`
- `npm --workspace @confluendo/ingestion-platform run ip16:staging-canary` (dry,
  confirmation absent -> hard-fail with no write)
- `npm --workspace @confluendo/console run build`
- Disposable Postgres with `INGESTION_TEST_DATABASE_URL` for the apply/rollback
  round-trip.

## Slice IP-17 - Vamo Production Inbox Delivery

Status: done and live-proven at bounded customer-zero scope. IP-17 merged to
`main` and IP-17.1 fixed the source-ref `canonical_key` package/apply contract.
The first live package attempt proved delivery into `confluendo_inbox` but
failed Vamo apply because package 10 was assembled by the old source-ref
payload contract. Package 10 is spent. A fresh package,
`production-inbox:vamo-place-intelligence-staging:approval:13`, was delivered
after IP-17.1 and Vamo applied it successfully (`applied=2`, `skipped=0`,
`rejected=0`). `/admin/ingestion` shows the package as applied.

Goal:

- Promote a reviewed, staging-proven Vamo place-intelligence package into Vamo
  production's `confluendo_inbox` schema.
- Keep Confluendo out of Vamo production product tables.
- Let Vamo own the later `apply_confluendo_shipment(...)` step into
  `public.location_canonicals` and `public.location_source_refs`.

Architecture decision:

- **Pure policy + package builder + target adapter.** The approval rules and
  package construction live in platform core; target writes are isolated behind
  the Postgres production-inbox adapter; the dashboard records approval only.
  This preserves the Confluendo provider boundary and the Vamo consumer apply
  boundary.

Implemented components:

- `web/packages/ingestion-platform/core/src/production-inbox-policy.ts`
  validates admin/AAL2/fresh-step-up, staging evidence, reviewed compatible dry
  run, production environment, bounds, no deletes, audit reason, and explicit
  `approved_for_production_inbox -> production_inbox_delivered` transition.
- `web/packages/ingestion-platform/core/src/shipment-package.ts` builds the
  logical package and item payloads. It intentionally leaves checksum
  calculation to target Postgres. IP-17.1 requires every
  `location_source_refs` item to carry the `canonical_key` that Vamo's apply
  function resolves, deriving it from the paired canonical item when the staged
  source-ref payload only carries `canonical_id`.
- `web/packages/ingestion-platform/adapters/target/src/postgres-production-inbox.ts`
  writes only to `confluendo_inbox.shipments` and
  `confluendo_inbox.shipment_items`, refuses staging guard artifacts, computes
  payload and package checksums in Vamo Postgres, and is idempotent on matching
  checksum.
- `web/packages/ingestion-platform/core/src/production-inbox-control.ts`
  records approval and delivery ledger rows in the Confluendo control DB.
- `web/packages/ingestion-platform/scripts/run-ip17-production-inbox.mjs`
  previews safely and hard-fails unless `CONFIRM_VAMO_PRODUCTION_INBOX=YES`,
  `--execute`, a fresh approval id, control DSN, production inbox DSN, and
  `VAMO_PRODUCTION_INBOX_ENVIRONMENT=production` are all present.
- `web/apps/confluendo-console/app/api/admin/ingestion/production-inbox/route.ts` records the
  dashboard approval decision only; it never receives Vamo production DB
  credentials.
- `web/apps/confluendo-console/app/admin/ingestion/production-inbox-control.tsx` surfaces the
  production inbox approval state beside the staging canary control.
- `supabase/migrations/20260701121500_confluendo_inbox_writer_digest_usage.sql`
  grants the least-privilege inbox writer access to the `extensions` schema so
  it can call `extensions.digest(...)`.
- `docs/platform/ingestion/PRODUCTION_INBOX_RUNBOOK.md` documents the live
  production inbox sequence and Vamo-owned apply step.

Hard guardrails:

- Production live runs are manual, confirmation-gated operations; CI and normal
  implementation validation still run dry only.
- No direct Confluendo grants on Vamo production product tables.
- No browser exposure of Vamo production DB credentials.
- No JavaScript checksum authority for production inbox packages; the adapter
  and Vamo apply function both use Vamo Postgres `extensions.digest(...)` over
  `jsonb::text`.
- No production delivery if `vamo_canary_app` or the staging guard sentinel is
  present on the target.
- Vamo-owned apply remains a manual/operator step after inbox delivery.

Validation:

- `npm --workspace @confluendo/ingestion-platform test`
- `npm --workspace @confluendo/ingestion-platform run ip17:production-inbox` (dry,
  confirmation absent -> hard-fail with no write)
- `npm --workspace @confluendo/console run build`
- Disposable Postgres with `INGESTION_TEST_DATABASE_URL` for:
  - production inbox schema and writer role,
  - SQL-computed item/package checksums,
  - idempotent inbox delivery,
  - Vamo-owned apply function,
  - staging guard refusal.

Live operational note:

- Do not retry package 10. It is a historical failed package.
- Package 13 is the successful reference proof for the inbox delivery plus
  Vamo-owned apply boundary.
- Any future shipment needs a new proposal/run and a new production inbox
  approval; do not reuse spent package ids.

## What Not To Build Yet

- No real provider scraping.
- No Google reusable content cache.
- No direct production target writes. IP-17 may deliver only to the consumer
  inbox schema after explicit approval and live gates.
- No autonomous AI-started ingestion without policy and operator approval.
- No connector marketplace.
- No physical standalone repo split until IP-15 boundary prep is merged and the
  boundary audit passes on `main`.
- For IP-16, no "promote to production" control and no production
  environment/DSN/adapter.
- No default backup/restore, physical log shipping, or raw replication path for
  Confluendo product data delivery. Use shipment packages through the delivery
  modes in `DATA_DELIVERY_ARCHITECTURE.md`.

## Slice IP-18 - Automated Batch Target Planning

Status: **done** (IP-18.0 merged). Foundation dry-run planning — no live
ingestion, no provider calls, no staging writes, no production inbox delivery,
and no database writes.

Goal:

Replace hand-created, city-by-city POI targets with a consumer-neutral batch
planner that expands geography × category specs into deterministic dry-run
units. Vamo EU POI (`vamo-place-intelligence`) is the first example consumer
profile, not platform hard-coding.

Delivered in IP-18.0:

- Batch spec model (`ingestion.batch_plan`) with explicit `targetEnvironment`
  metadata (never inferred from `targetKey`).
- Pure `buildBatchPlan()` expansion, dedupe, blocked-unit reasons, coverage
  summary, and schedule-proposal integration via existing scorecard policy.
- Vamo EU POI sample fixture (`fixtures/platform/ip18/vamo-eu-poi-batch.yaml`).
- CLI dry-run: `npm --workspace @confluendo/ingestion-platform run ip18:batch-plan`.
- Dashboard read-only preview panel on `/admin/ingestion` (bundled sample only).
- Docs: `BATCH_TARGET_PLANNING.md`.

Architecture decision: Confluendo owns the planner; Vamo is a consumer example.
See IP-15 extraction boundary — do not encode Vamo-specific policy into the
platform core beyond fixtures and sample profiles.

Safety:

- `safetyMode` must be `dry_run`; `staging_write` and `production_write` are
  rejected at parse and plan time.
- Generated target keys remain environment-neutral (`vamo-place-intelligence`,
  not `vamo-place-intelligence-staging`).

## Slice IP-18.1 - Dashboard Batch Queue Read Model

Status: **done** (IP-18.1 merged). Queue and progress projection only — no live
ingestion, no provider calls, no staging writes, no production inbox delivery,
and no database writes.

Goal:

Turn IP-18.0's bundled batch plan into a queue/progress read model the Confluendo
console can show as operational state: coverage cards, country/category matrix,
grouped units, blocker summaries, and progress counters.

Delivered in IP-18.1:

- `buildBatchQueueSnapshot()` with `BatchQueueSnapshot`, `BatchQueueGroup`,
  `BatchQueueItem`, coverage, progress, and blocker summaries.
- Bundled Vamo EU POI sample queue fixture (`sampleVamoEuPoiBatchQueueSnapshot`).
- Console **Batch Queue** section on `/admin/ingestion` (read-only, no mutation
  controls).
- Unit tests for grouping, coverage (36 units), blockers, progression math, and
  env-neutral target keys.

## Slice IP-18.2 - Persistent Batch Queue / Control Table

Status: **done** (IP-18.2 merged). Writes only to Confluendo control-plane queue
tables (`ingestion_batch_plans`, `ingestion_batch_queue_items`). No provider
calls, no Vamo staging writes, no production inbox delivery.

Goal:

Persist IP-18.1 batch queue state so the dashboard can read live queue rows from
the control DB instead of only bundled sample data.

Delivered in IP-18.2:

- Idempotent control schema tables with status CHECK constraints matching the
  IP-18.1 queue status set (`CONTROL_TABLES` now 20).
- Pure persistence mapper and idempotent `persistBatchQueueSnapshot()` upserts.
- `loadBatchQueueSnapshot()` live read loader with undefined-table fallback.
- Console prefers live control-plane rows when present; labels **Live control
  plane** vs **Sample preview**.
- Seed generator: `npm --workspace @confluendo/ingestion-platform run ip18:batch-queue-seed`.
- Disposable Postgres smokes: apply schema, persist sample twice, reload 36 units.

Ops note: live dashboard queue data appears only after `control_schema.sql` (with
IP-18.2 tables) is applied to the live Confluendo control DB and the seed or
persist helper has run. Merge alone correctly falls back to sample preview when
tables or rows are absent.

## Slice IP-18.3 - Operator Scheduling Mutations

Status: **done** (IP-18.3 merged; live-verified). Writes only to Confluendo
control-plane queue items and audit log. No provider calls, no Vamo staging
writes, no production inbox delivery.

Goal:

Let an authenticated operator/admin move a persisted batch queue from
`ready_for_dry_run` to `dry_run_ready` from the console, with an audit reason,
without executing ingestion.

Delivered in IP-18.3:

- Pure policy: `evaluateBatchQueueScheduleDryRun()` requires project scope,
  operator/admin role, AAL2 when MFA is required, `dry_run` safety mode, explicit
  target environment, eligible `ready_for_dry_run` rows, and a non-empty audit
  reason.
- Control mutation: `scheduleBatchDryRun()` updates only
  `ingestion_batch_queue_items.status` (`ready_for_dry_run` → `dry_run_ready`)
  and records `schedule_batch_dry_run` in `ingestion_audit_log`.
- API route: `POST /api/admin/ingestion/batch-queue/schedule` with same-origin
  JSON and session-derived Confluendo admin principal.
- Console control: audit-reason form + button in the IP-18 Batch Queue section;
  disabled for sample/error data, viewer role, missing AAL2, or no eligible
  units.
- Live-read failures for IP-14/IP-18 now surface as **Live read failed · sample
  fallback** instead of being mislabeled as ordinary sample preview.
- Bootstrap grant update: `confluendo_app` can update only `status` and
  `updated_at` on `ingestion_batch_queue_items`.

Live verification evidence:

- Dashboard scheduled **36 units** from `ready_for_dry_run` → `dry_run_ready`.
- Explicit environment: **staging** (never inferred from target key).
- Audit id: **15** recorded in `ingestion_audit_log` for the schedule action.

Ops note: after merge, re-run `control_bootstrap_confluendo.sql` on the live
Confluendo control DB so the runtime role receives the queue-item `UPDATE` grant.
Without that grant, the scheduling route fails closed.

## Slice IP-18.4 - Dry-Run Execution Orchestration

Status: **done** (IP-18.4 merged; live-proven). Executes bounded fixture-only dry runs from
`dry_run_ready` queue state and writes only Confluendo control-plane execution
state. No live provider calls, no Vamo staging writes, no production inbox
delivery.

Goal:

Run bounded dry-run execution against persisted queue units, store per-unit
reports/checkpoints/blockers in control-plane tables, and surface execution
progress in the dashboard.

Delivered in IP-18.4:

- Pure policy: `evaluateBatchDryRunExecution()` bounds eligible `dry_run_ready`
  units by target key, explicit `target_environment`, max units, and audit
  reason/operator context.
- Fixture simulator: `simulateBatchDryRunUnit()` — deterministic, no network.
- Control execution: `executeBatchDryRun()` with idempotent
  `ingestion_batch_dry_run_executions` rows and queue-item status transitions
  (`dry_run_running` → `dry_run_succeeded` / `dry_run_blocked`).
- Status extension on `ingestion_batch_queue_items` for execution lifecycle.
- CLI: `npm --workspace @confluendo/ingestion-platform run ip18:batch-dry-run`
  (preview default; `--execute` requires `CONFIRM_CONFLUENDO_BATCH_DRY_RUN=YES`).
- Dashboard: execution counters, latest execution summary, per-unit dry-run
  report column (read-only).
- Disposable Postgres smokes mandatory.

Operational note:

- Applying only the pre-IP-18.4 control schema leaves live execute blocked with
  `relation "ingestion_platform.ingestion_batch_dry_run_executions" does not
  exist`. After IP-18.4, live Confluendo control DBs must receive both the
  updated `control_schema.sql` and `control_bootstrap_confluendo.sql`.
- Before applying either SQL file, positively confirm the SQL editor is pointed
  at the Confluendo control DB (`confluendo-control`, project ref
  `agrcvzlkorlzwoxtkcft`). The presence of `confluendo_app` is not sufficient
  proof because Postgres roles are cluster-level.
- The runtime role (`confluendo_app`) needs insert/update on
  `ingestion_batch_dry_run_executions` and column-scoped update on
  `ingestion_batch_queue_items.status`, `run_report`, `blockers`, and
  `updated_at`, plus audit-log insert and sequence usage for identity-backed
  inserts. These are Confluendo control-plane grants only; they do not grant
  Vamo staging or production access.
- On PowerShell, use the direct node form for execute mode after `npm run build`
  from `web/packages/ingestion-platform`, because npm may parse forwarded
  `--max-units`/`--audit-id` flags as npm config before the script sees them.

Live evidence:

- IP-18.3 scheduling audit id **15** moved 36 units from `ready_for_dry_run` to
  `dry_run_ready`.
- IP-18.4 execution key `batch-dry-run:vamo-eu-poi-sample:audit:15` executed
  the first bounded 3-unit dry-run against the live Confluendo control DB.
- Execution id **1** finished `succeeded`; execution audit row **16** was
  recorded.
- Queue after execution: **3** `dry_run_succeeded`, **33** `dry_run_ready`.
- Executed units: `vamo-place-intelligence:rome-italy:poi`,
  `vamo-place-intelligence:paris-france:landmark`,
  `vamo-place-intelligence:barcelona-spain:landmark`.
- Dashboard reports for all three show `wroteToTarget=false`; no live provider,
  Vamo staging, or Vamo production writes occurred.
- After IP-10.1 source expansion and PR #135's target-row counting fix,
  `PrepareDryRun` re-ran IP-18.4 for the next wave candidates. Execution id
  **4** recorded audit id **33** and left
  `vamo-place-intelligence:paris-france:landmark` plus
  `vamo-place-intelligence:barcelona-spain:landmark` as
  `dry_run_succeeded`, each with `insert_count=2`, `wroteToTarget=false`, and
  no blockers.

## Slice IP-18.5 - Staged Batch Canary Waves

Status: **active — first live 1-unit staging wave succeeded; continue governed
ramp**. IP-18.5 is the first batch slice that may touch a consumer DB
again. **Production is forbidden.** Vamo staging writes must reuse the existing
IP-16 `applyPostgresStagingCanary` adapter — no second staging write path and no
aggregate multi-unit direct write.

Source of truth:

- `docs/platform/ingestion/STAGED_BATCH_CANARY_WAVES.md`

Core design decision:

A **staging canary wave** is a bounded sequence of **independent per-unit IP-16
staging canaries**. Each unit is sentinel-proven, atomic, individually ledgered,
idempotent, and individually rollback-able. IP-18.5 orchestrates eligibility,
ramp, approval, ordering, stop-on-first-failure, and control-plane state only.

### IP-18.5.0 — Design spec (this slice)

Goal: define the wave model, state machine, eligibility, ramp, approval, partial
failure, resume/replay, dashboard read surfaces, and ops gates before any code or
SQL lands.

Delivered in IP-18.5.0:

- `STAGED_BATCH_CANARY_WAVES.md` — authoritative design for batch staging waves.
- BUILD_SLICES + BATCH_TARGET_PLANNING updates with IP-18.4 live evidence and
  IP-18.5 phasing.

State machine (queue item extension; no production states):

```text
dry_run_succeeded -> staging_canary_ready -> staging_canary_approved
  -> staging_canary_running -> staging_canary_succeeded | staging_canary_blocked
```

Key gates documented:

- Eligibility: `dry_run_succeeded` only, `wroteToTarget=false`, explicit
  `target_environment='staging'`, explicit `target_key='vamo-place-intelligence'`,
  `STAGING_CANARY_MAX_ROWS=50` per unit, wave `maxUnits` + `maxTotalRows` bounds.
- Ramp: first live wave hard-capped at **1 unit** in approval and execution
  policy; widening requires explicit new operator approval after prior staging
  success; "all 33 remaining units" forbidden as first wave.
- Approval: `ingestion_admin` + verified AAL2 + fresh MFA step-up + audit reason;
  reuse `STAGING_CANARY_APPROVAL_MAX_AGE_MS` (15 minutes); control DB only.
- Partial failure: **stop-on-first-failure**; succeeded units stay succeeded.
- Replay: skip succeeded units; per-unit idempotency via IP-16 shipment keys.

Live baseline (IP-18.4):

- Execution key `batch-dry-run:vamo-eu-poi-sample:audit:15` succeeded for 3 units.
- Queue: **3** `dry_run_succeeded`, **33** `dry_run_ready`.
- First staging wave should target 1 of the 3 succeeded units, not dry-run-ready rows.

Acceptance criteria (IP-18.5.0):

- Design spec complete; no functional code, no SQL applied, no live canary execution.
- IP-16 adapter remains the only staging write boundary.
- Production forbidden; `ip15:boundary-audit` unchanged.

Validation (IP-18.5.0):

- `git diff --check`
- Docs-only diff; no secrets.

### IP-18.5 implementation status

| Phase | Scope |
| --- | --- |
| IP-18.5.0 | Done — design spec |
| IP-18.5.1 | Done — pure wave eligibility/ramp/approval policy + control schema (`CONTROL_TABLES` 21 -> 23) + mandatory DB smokes |
| IP-18.5.2 | Done — CLI wave executor reusing per-unit `applyPostgresStagingCanary`; first-wave hard cap enforced in approval and execution |
| IP-18.5.3 | Done in the current console path — dashboard approval surface and read-only wave state |
| IP-18.5.4 | Active — two refreshed live 1-unit staging waves succeeded; continue ramp before widening |

Live IP-18.5 evidence:

- Earlier attempts against the 5-row fixture failed closed and exposed two useful
  fixes: PR #135 made dry-run reports count target rows rather than source rows,
  and PRs #136-#138 added the operator helper while keeping resets within
  `confluendo_app` grants and avoiding unintended unit selection.
- Refreshed IP-18.4 evidence after IP-10.1: execution id **4**, audit id **33**,
  Paris landmark and Barcelona landmark both `dry_run_succeeded` with
  `insert_count=2`, `wroteToTarget=false`, and no blockers.
- Dashboard approved a 1-unit wave with approval audit id **34** for
  `vamo-place-intelligence:paris-france:landmark`; max rows was **2**.
- CLI execution completed with wave status **succeeded**, execution audit id
  **36**, shipment id **4**, and shipment key
  `batch-staging-canary-wave:batch-staging-canary:vamo-eu-poi-sample:1:vamo-place-intelligence:paris-france:landmark:Approve-fixed-IP-18.5-ra:unit:vamo-place-intelligence:paris-france:landmark`.
- Live Vamo staging verification found the source ref and canonical joined by
  `location_source_refs.canonical_id = location_canonicals.id`:
  `provider='fsq_os_places'`,
  `source_place_id='fsq_paris_louvre_landmark'`,
  `canonical_id='0b9523e6-07bd-510a-ba3e-d22dfdbecf9a'`,
  `canonical_key='fsq-paris-louvre-landmark'`,
  `display_name='Louvre Pyramid'`, `feature_type='landmark'`, coordinates
  `(48.8606, 2.3376)`, with both rows created at
  `2026-07-03 23:03:21.699871+00`.
- Dashboard approved a second 1-unit wave with approval audit id **37** for
  `vamo-place-intelligence:barcelona-spain:landmark`; max rows was **2**.
- CLI execution completed with wave status **succeeded**, execution audit id
  **39**, shipment id **5**, and shipment key
  `batch-staging-canary-wave:batch-staging-canary:vamo-eu-poi-sample:1:vamo-place-intelligence:barcelona-spain:landmark:Approve-fixed-IP-18.5-ra:unit:vamo-place-intelligence:barcelona-spain:landmark`.
- Live Vamo staging verification found the Barcelona source ref and canonical:
  `provider='fsq_os_places'`,
  `source_place_id='fsq_barcelona_gothic_quarter_landmark'`,
  `canonical_id='2b89c45b-894b-5f87-9560-d3ba23d298b9'`,
  `canonical_key='fsq-barcelona-gothic-quarter-landmark'`,
  `display_name='Gothic Quarter'`, `feature_type='landmark'`, coordinates
  `(41.3839, 2.1763)`, with both rows created at
  `2026-07-03 23:37:12.9848+00`.
- This proof wrote Vamo staging only through the IP-16 adapter. It did not write
  to Vamo production and did not call a live provider.

Operational decision: continue the IP-18.5 staging ramp one unit at a time over
the refreshed IP-10.1 supply. Paris landmark and Barcelona landmark are now both
`staging_canary_succeeded`; the next ramp step should either continue another
single-unit wave or explicitly approve a small widening only after reviewing the
latest dashboard state.

Future slices:

- **IP-18.6** — production inbox package waves, reusing the IP-17 delivery
  boundary for staging-proven units. Design source:
  [PRODUCTION_INBOX_PACKAGE_WAVES.md](./PRODUCTION_INBOX_PACKAGE_WAVES.md).
- **IP-18.7** — autonomous batch orchestrator, converting source/target policy
  into unattended dry-run/staging/production-inbox progress inside configured
  bounds.

## Recommended Immediate Next Slice

**IP-18.7.4 — Operator-controlled autonomy ramp console controls** is the next
product slice. The foundation PR has added the `ramp_mode` policy column,
audited `promote_autonomy_ramp(...)` SECURITY DEFINER function, app-role
EXECUTE-only grant, and executor effective-bound enforcement. Next, add the
operator-facing console card/route: admin + fresh AAL2, typed confirmation,
readiness evidence, promote-to-next only, and unconditional demote/pause.
Hosted scheduler work follows as IP-18.7.5.

Previously recommended:

- **Consumer display contract** — **done** — consumer contract manifest declares
  operator-facing queue fields; the core batch queue read model resolves them
  into `BatchQueueItem.displayFields`; React renders those fields generically.
  Vamo declares `POI type` from `scope.category` with `feature_type=...` only as
  secondary technical detail.
- **IP-18.6.6 — Consumer Apply Control** — **done** — gated console/API apply
  via `VAMO_PRODUCTION_INBOX_APPLY_DATABASE_URL`, preflight/result evidence,
  apply adapter + least-privilege `confluendo_inbox_apply` role, post-apply
  telemetry refresh on dashboard reload.
- **IP-18.6.5 — Delivery content equivalence** — **done** — deterministic
  `stagedContentHash` at approval, recompute/compare before inbox delivery,
  blocked-state persistence, Delivery view evidence labels. Live proof:
  approval `62` -> delivery audit `63` -> package
  `batch-production-inbox:vamo-eu-poi-sample:wave:62:unit:vamo-place-intelligence:barcelona-spain:landmark`
  -> Vamo apply marked both inbox items `applied`.
- **IP-18.6.4 — Apply Telemetry** — **done** — read-only inbox polling,
  control-plane mirror, dashboard states, persisted delivery blocks. Live proof
  required explicit RLS `SELECT` policies for the pooler login role
  `confluendo_inbox_telemetry_app` on `confluendo_inbox.shipments`,
  `shipment_items`, and `apply_log`; group-role grants alone returned no rows.

### IP-18.7.0 — done (foundation only)

Status: **implemented** — no live executor, no provider calls, no staging/prod writes.

Landed:

- `ingestion_autonomy_policies` + `ingestion_autonomy_runs` (`CONTROL_TABLES` 23 → 25).
- `autonomous_agent` actor type on commands and audit log.
- Pure `evaluateAutonomyCycle()` in `autonomy-policy.ts`.
- Read model + `/admin/ingestion` autonomy panel (read-only).
- Telemetry name contract reserved (`autonomy.cycle.*`, `autonomy.action.applied`).

Ops: apply updated `control_schema.sql` and `control_bootstrap_confluendo.sql`
to the live Confluendo control DB for live dashboard rows; code merge alone falls
back to sample preview when tables are absent.

### IP-18.7.1 — done (bounded control-plane executor)

Status: **implemented** — one bounded control-plane action per cycle; no live staging execution.

Landed:

- `autonomy-executor.ts` with `previewAutonomyCycle()` / `executeAutonomyCycle()`.
- CLI `npm run ip18:autonomy-cycle` (preview default; execute gated by
  `CONFIRM_CONFLUENDO_AUTONOMY_CYCLE=YES`).
- May schedule dry-run, execute dry-run (fixture/control-plane), or approve staging wave.
- Records `ingestion_autonomy_runs` + `ingestion_events` telemetry.
- Does **not** execute live staging canary writes or production inbox delivery.

### IP-18.7.2 — implemented (policy ramp modes)

Status: **implemented** — control-plane policy vocabulary only; no live SQL or
consumer writes.

Scope:

- Name autonomy ramp modes in code and docs: `bootstrap`, `staging_ramp`,
  `volume_ramp`, `steady_state`.
- Treat the current `2 units/day` policy as **bootstrap proof**, not the
  steady-state ingestion model.
- Add pure ramp-promotion policy: only an admin operator can widen policy, the
  agent cannot widen itself, and modes advance one step at a time.
- Surface the current ramp mode and profile warnings in `/admin/ingestion`.
- Keep live policy widening as an owner/operator SQL step with audit evidence;
  this slice does not mutate the live control DB.

### IP-18.7.3 — implemented (scheduler foundation)

Status: **implemented** — bounded recurring control-plane autonomy cycles; no
provider calls, no live staging writes, no production inbox delivery.

Scope:

- Add `runAutonomyScheduler()` as a thin loop over the existing one-cycle
  executor.
- Add CLI `npm run ip18:autonomy-scheduler` (preview default; execute gated by
  `CONFIRM_CONFLUENDO_AUTONOMY_SCHEDULER=YES`).
- Stop cleanly on policy pause, no eligible work, human-runbook deferral,
  idempotent terminal replay, or max-cycle cap.
- Record terminal policy pauses through existing autonomy run/event telemetry;
  pause run keys include the UTC day and pause code so recurring schedulers
  preserve fresh daily pause visibility.
- Keep the scheduler control-plane-only; it composes existing approved
  transitions and does not introduce a target write path.

### IP-18.7.4 — foundation implemented (operator ramp promotion)

Status: **foundation implemented** — control-plane schema/function and executor
enforcement only; console controls are the follow-up PR.

Landed:

- `ingestion_autonomy_policies.ramp_mode` with CHECKed modes and backfill from
  legacy `summary.rampMode` / `summary.ramp.mode`.
- `ingestion_platform.promote_autonomy_ramp(...)` as the only app-callable
  mutation: transition-legal, optimistic-concurrency guarded, audit/event
  atomic, and `steady_state` locked.
- `confluendo_app` receives EXECUTE on the function, but no UPDATE grant on
  `ingestion_autonomy_policies`.
- Executor effective bounds:
  `min(owner-approved policy ceiling, active ramp profile cap)`.
- Run keys include `ramp:<mode>` so mode changes refresh idempotency without a
  policy-version bump.
- Pure promotion policy now distinguishes promotion from demotion: widening
  requires admin operator + fresh AAL2 + no active blockers; narrowing can be
  done immediately with audit reason.

Next PR: `/admin/ingestion` ramp card and API route that call the function only
after app-layer auth/readiness checks.

### IP-18.6.0 — design ready (production inbox package waves)

Status: **design ready** — [PRODUCTION_INBOX_PACKAGE_WAVES.md](./PRODUCTION_INBOX_PACKAGE_WAVES.md)
defines the production package-wave contract before implementation.

Scope:

- Scale the proven IP-17 production-inbox path from one manually approved
  package to bounded package waves over staging-proven units.
- Keep consumer production product-table writes out of Confluendo. Delivery is
  to the consumer inbox; consumer apply remains consumer-owned.
- Reuse `buildProductionInboxPackage(...)` and
  `deliverPostgresProductionInboxPackage(...)`; do not create a second
  production delivery adapter.
- Track package wave state, package/checksum evidence, consumer apply status,
  blockers, and corrective actions in the Confluendo control plane.
- Keep the first live Vamo run to one staging-proven unit, one fresh approval,
  one confirmation-gated inbox delivery, and Vamo-owned apply verification.

Recommended implementation split:

- **IP-18.6.1** — **done** — package-wave policy, schema, read model, and DB
  smokes; no live delivery (`CONTROL_TABLES` 25 → 27).
- **IP-18.6.2** — **done** — dashboard approval route/card with admin + AAL2 +
  fresh MFA; real audit id owns wave/package keys; no delivery.
- **IP-18.6.3** — **done / live-proven** — expired approval release +
  confirmation-gated delivery CLI (`ip18:production-package-wave`) reusing
  IP-17 builder/adapter. Live proof: approval `58` -> delivery audit `59` ->
  package
  `batch-production-inbox:vamo-eu-poi-sample:wave:58:unit:vamo-place-intelligence:paris-france:landmark`
  -> Vamo apply marked both inbox items `applied`.
- **IP-18.6.4** — **done** — read-only consumer apply telemetry
  (`VAMO_PRODUCTION_INBOX_TELEMETRY_DATABASE_URL`), control-plane mirror,
  dashboard states, persisted delivery-block state. The live Vamo proof read
  package wave `58` / delivery audit `59` back through
  `confluendo_inbox_telemetry_app` after adding explicit login-role RLS
  policies, and advanced the queue row to `consumer_applied`.
- **IP-18.6.5** — **done** — delivery content equivalence hardening:
  `stagedContentHash` on wave-item `staging_evidence`, compare before IP-17
  inbox write, block with audit evidence on drift. Live proof: package wave
  `62` delivered and applied `fsq_barcelona_gothic_quarter_landmark` as
  `fsq-barcelona-gothic-quarter-landmark` / `Gothic Quarter`.
- **IP-18.6.6** — **done** — Consumer Apply Control. Gated console/API action
  calls only Vamo's existing `confluendo_inbox.apply_confluendo_shipment(...)`
  boundary through `VAMO_PRODUCTION_INBOX_APPLY_DATABASE_URL`, then dashboard
  reload refreshes apply telemetry.
- **IP-18.6.7** — **done** — autonomy hook after package waves, apply
    telemetry, content equivalence, and consumer apply control are proven.
    The agent may approve a production package wave and deliver an already
    approved package only when policy allows `approve_production_package_wave`
    / `deliver_production_package_wave`; it pauses at consumer apply.

### IP-18.7.4+ — recommended next

Scope:

- Clarify the Agent tab run surface: console = preview/status/runbook; trusted
  ops runtime = executes one bounded cycle; Delivery tab = production package
  delivery and Apply-to-Vamo gates.
- Operator-controlled ramp promotion card in the admin console, calling the
  already-landed DB-guarded function with app-layer auth/readiness checks.
- **IP-18.7.5 — hosted scheduler foundation** — **done** — Vercel-cron-compatible
  server route wrapping `runAutonomyScheduler()` with bearer-secret auth,
  explicit hosted execution confirmation, env-driven project/policy identity,
  bounded max-cycle parsing, and separate production-delivery confirmation.
  The route refuses leaked staging-canary DSNs and never calls consumer apply.
- Autonomous corrective actions when explicitly allowed by policy.

### IP-18.7.5 — implemented (hosted scheduler foundation)

Status: **implemented** — hosted/server runtime entrypoint only; no new
scheduler write path and no consumer apply.

Landed:

- `autonomy-hosted-scheduler.ts` pure helper for server env parsing and
  bearer/cron-secret authorization.
- `/api/admin/ingestion/autonomy/scheduler` route in the Confluendo console.
- Vercel cron schedule file in `web/apps/confluendo-console/vercel.json`.
- Route gates:
  - `CONFLUENDO_AUTONOMY_SCHEDULER_SECRET` or Vercel's `CRON_SECRET`;
  - `CONFIRM_CONFLUENDO_HOSTED_AUTONOMY_SCHEDULER=YES`;
  - `INGESTION_CONTROL_DATABASE_URL`;
  - `CONFLUENDO_AUTONOMY_SCHEDULER_PROJECT_KEY`;
  - `CONFLUENDO_AUTONOMY_SCHEDULER_POLICY_KEY`.
- Production package delivery is passed through only with
  `CONFIRM_CONFLUENDO_AUTONOMY_PRODUCTION_DELIVERY=YES`,
  `VAMO_PRODUCTION_INBOX_DATABASE_URL`, and
  `VAMO_PRODUCTION_INBOX_ENVIRONMENT=production`.
- The route refuses `VAMO_STAGING_CANARY_APP_DATABASE_URL` and does not call
  live staging execution or Consumer Apply Control.

### IP-18.8.15 — implemented (Supabase Storage artifact profile)

**Status:** done — the existing private `snapshot-artifacts` buckets in
Confluendo Control staging and production are first-class trusted-worker
artifact stores. The `supabase` profile derives the only accepted S3 endpoint
from the project reference and reuses the existing S3-compatible adapter; it
does not create an AWS dependency or a second storage path.

Deliverables:

- Pure configuration profile:
  `CONFLUENDO_SNAPSHOT_ARTIFACT_STORE=supabase` plus project reference, bucket,
  region, optional prefix, and generated Supabase S3 access credentials.
- The credentials are passed only into the trusted worker's S3-compatible
  client. They never reach the console/browser, Vamo, API responses, logs, or
  control-plane records.
- `ip18:artifact-store-preflight` calls `HeadBucket` only. It proves the
  worker can access the configured private bucket without reading or writing a
  snapshot artifact.
- Existing immutable release keys and final bundle SHA-256 verification remain
  the content-integrity authority. The commissioning/activation request lease
  remains the single-worker concurrency authority; Supabase Storage object
  versioning is not assumed.

No control schema, Vamo schema, provider call, staging write, production inbox
delivery, consumer apply, or console route changed in this slice.

Worker provisioning checkpoint:

1. In each Confluendo Control project, enable Supabase Storage S3 access and
   create a generated S3 access-key pair for the trusted worker environment.
2. Store the pair only in the respective staging or production job-secret
   store. Supabase S3 access keys have project Storage scope, so they must not
   be placed in Vercel browser variables, local commits, or Vamo configuration.
3. Run `ip18:artifact-store-preflight` in staging before configuring the same
   profile in production.

### IP-18.8.14 — implemented (operator-confirmed snapshot activation)

**Status:** done — a separately confirmed activation request is
now required before a trusted worker can bind a registered source release and
reconcile its queue supply. **Not** automatic activation, **not** browser
artifact access, **not** provider acquisition, **not** Vamo writes, **not**
inbox delivery, and **not** consumer apply.

Deliverables:

- `ingestion_snapshot_activation_requests` plus security-definer
  `create_snapshot_activation_request`,
  `claim_snapshot_activation_request`, and
  `complete_snapshot_activation_request`. The app role may create/read through
  approved functions only; claim/complete remain owner/worker-only.
- Pure helpers for parsing, policy gates, state transitions, and safe operator
  presentation.
- Console POST route `/api/admin/ingestion/snapshot-activation/request` with
  server-derived plan/release identity, admin + AAL2 + fresh step-up, audit
  reason, and an explicit dropdown confirmation. The route never imports the
  activation executor or artifact-store configuration.
- `SnapshotActivationControl` in Queue, after commissioning: it displays the
  registered release, request state, and recovery-safe next action.
- `ip18:snapshot-activation-worker` trusted CLI/job worker: claims one request,
  invokes the existing IP-18.8.11 artifact verification/binding/reconciliation
  path, and completes `activated` or `failed` with a safe operator result.

State model:

`requested → running → activated`; failures move to `failed`. A commissioning
request reaching `activation_pending` is the required input. The operator
request and worker execution are distinct; no queue binding occurs when the
browser submits the request.

Control-plane promotion evidence (2026-07-15):

- The reviewed `control_schema.sql` and `control_bootstrap_confluendo.sql` pair
  was applied to **Confluendo Control Staging**, then promoted unchanged to
  **Confluendo Control production** in the same release window.
- Both environments verified app-role create/read-only access and worker-only
  claim/complete behavior. `INGESTION_TEST_DATABASE_URL` remains reserved for
  disposable database smokes, never either control environment.

### IP-18.8.13 — implemented (operator-confirmed snapshot release commissioning)

**Status:** done — durable control-plane commissioning requests for bounded FSQ
snapshot acquisition. **Not** browser/provider acquisition, **not** artifact or
S3 exposure in console JSON/props, **not** automatic activation, **not** Vamo
writes, **not** inbox delivery, **not** consumer apply.

Deliverables:

- `ingestion_snapshot_commission_requests` plus security-definer
  `create_snapshot_commission_request`, `claim_snapshot_commission_request`, and
  `complete_snapshot_commission_request`. App role may create/read via approved
  functions only; claim/complete remain owner/worker-only.
- Pure helpers for request parsing, policy evaluation, state transitions, and
  safe operator presentation in core.
- Console POST route `/api/admin/ingestion/snapshot-commission/request` with
  admin + AAL2 + fresh step-up enforcement. Records requests only; never calls
  the provider or returns secrets.
- `SnapshotCommissionControl` in the operator queue workflow with bounded scope
  selection, status/recovery presentation, and no browser-side execute button.
- `ip18:snapshot-commission-worker` trusted CLI/job worker: atomically claims
  one request, invokes existing IP-18.8.10 acquisition with server/job FSQ
  token and IP-18.8.12 artifact store, registers the release, and ends in
  `activation_pending`. Activation remains the separately confirmed IP-18.8.11
  action.

State model:

`requested → running → release_registered → activation_pending`; failures move
to `failed`. Release registration never activates automatically.

Control-plane deployment checkpoint (2026-07-14):

- A distinct `confluendo-control-staging` environment now exists. The
  IP-18.8.13 `control_schema.sql` and `control_bootstrap_confluendo.sql` pair
  was applied and structurally verified there with least-privilege app access.
- Future schema-affecting Confluendo releases must use that staging environment
  first, then promote the identical reviewed SQL pair to control production in
  the same release window. The initial single-environment exception is closed.

Human provisioning prerequisite:

1. Schedule the trusted worker (`ip18:snapshot-commission-worker`) on a
   server/job host with owner `INGESTION_CONTROL_DATABASE_URL`, FSQ catalog
   token, artifact-store config, and
   `CONFIRM_CONFLUENDO_SNAPSHOT_COMMISSION_WORKER=YES`.

### IP-18.8.12 — implemented (hosted snapshot artifact store)

**Status:** done — server/job-only S3-compatible snapshot artifact store for
hosted scheduler staging/delivery reads of already-activated snapshots. **Not**
automatic acquisition/activation/delivery, **not** Vamo writes, **not** inbox
delivery, **not** consumer apply, **not** browser artifact access.

Deliverables:

- `adapters/artifact/` — S3-compatible `SnapshotArtifactStore` adapter with
  injectable client seam; dynamic `@aws-sdk/client-s3` import keeps SDK out of
  console/browser bundles.
- `snapshot-artifact-store-config.ts` — pure env parser/factory for trusted job
  contexts only (`CONFLUENDO_SNAPSHOT_ARTIFACT_STORE=s3`, bucket, region,
  optional endpoint/prefix). Credentials from server/job env only.
- Immutable writes (no overwrite), unsafe-key refusal, bundle SHA-256
  verification from artifact contents (never ETag), exactly
  `source.jsonl` / `release.json` / `coverage-report.json`.
- Wired into IP-18.8.10 acquisition execute, IP-18.8.11 activation CLI,
  artifact-aware staging/production delivery, and hosted autonomy scheduler.
  Local `--artifact-store-dir` / `INGESTION_ARTIFACT_STORE_DIR` unchanged.
- Hosted scheduler fails closed without valid S3 artifact-store config.
- Boundary audit: no artifact-store credentials, bucket names, or S3 SDK in
  console runtime.

Human provisioning prerequisite:

1. Private Confluendo-owned S3-compatible bucket (AWS S3, R2, MinIO, etc.).
2. Least-privilege job credential restricted to that bucket/prefix
   (`GetObject`, `PutObject`, `HeadObject` on snapshot artifact keys only).
3. Server/job-only environment configuration on the hosted scheduler and trusted
   CLIs — never in console client components, API responses, or browser props.

Vamo has no artifact-store credentials; artifacts are never browser-accessible.

Local limitation: trusted CLIs may still use `--artifact-store-dir` on a trusted
host. Hosted scheduler requires S3 config; pipeline execution materializes
hosted bundles to a temp dir server-side before running the existing pipeline.

### IP-18.8.11 — implemented (snapshot release activation)

**Status:** done — verified local snapshot release activation into
`vamo-eu-full-data-v1` with plan-scoped bindings, supply reconciliation, and
artifact-aware staging/approval/delivery. **Not** provider calls, **not** Vamo
writes, **not** inbox delivery, **not** consumer apply during activation.

Deliverables:

- `ingestion_snapshot_release_plan_bindings` plus security-definer
  `activate_snapshot_release(...)` — one active binding per batch plan; app role
  may read bindings and execute activation but cannot directly update registry or
  binding rows.
- Pure helpers `reconcileActivatedSnapshotQueue` and
  `verifySnapshotActivationArtifact` with thin control/artifact adapters.
- `ip18:snapshot-activate` — preview is write-free; execute requires
  `CONFIRM_CONFLUENDO_SNAPSHOT_RELEASE_ACTIVATION=YES`,
  `INGESTION_CONTROL_DATABASE_URL`, `--release-id`, `--plan-key`,
  `--artifact-store-dir`, and `--audit-reason`. Resolves `file://` artifacts only
  beneath the trusted store root and verifies bundle identity before any DB
  mutation.
- Supply reconciliation preserves terminal/in-flight queue evidence; only
  source-reconcilable rows refresh. Activation binding plus reconciliation commit
  atomically.
- Staging/production CLIs and production approval resolve the active binding,
  verify artifacts under `INGESTION_ARTIFACT_STORE_DIR` / `--artifact-store-dir`,
  record `stagedContentHash` evidence at staging execution, and fail closed on
  active-release plans without bundled-fixture fallback.
- Workflow Navigator Source Release stage shows safe binding metadata only (no
  artifact URI/path in browser code).

Activation vs acquisition:

- **Acquisition (IP-18.8.10)** — fetch/normalize provider export, store immutable
  artifacts, register `activation_ready` metadata.
- **Activation (IP-18.8.11)** — bind a registered release to a batch plan and
  reconcile queue supply from the verified artifact. No provider calls, no Vamo
  writes, no inbox delivery, no consumer apply.

### IP-18.8.10 — implemented (source acquisition and snapshot registry)

**Status:** done — provider-facing FSQ acquisition boundary, immutable artifact
store adapter, and control-plane release registry. **Not** snapshot activation,
**not** queue reseed, **not** console source-token UI, **not** FSQ calls from
console/scheduler/queue/delivery paths.

Deliverables:

- `source-acquisition-contract.ts` — provider-neutral release record with
  statuses `acquired`, `validated`, `rejected`, `activation_ready`, `superseded`.
- `fsq-os-places-catalog-acquire.ts` — sole FSQ HTTP boundary; bounded
  country/category scopes; preview is write-free; execute requires
  `FSQ_OS_PLACES_CATALOG_SERVICE_API_KEY` from server/job secrets only.
- `snapshot-artifact-store.ts` — immutable artifact key
  `{sourceKey}/{releaseId}/{outputSha256}` with local test store and bundle
  checksum verification (`source.jsonl`, `release.json`, `coverage-report.json`).
- `ingestion_snapshot_releases` table plus owner-controlled
  `register_snapshot_release(...)` with audit/event evidence; `confluendo_app`
  may read and execute registration but cannot directly update release status.
- `ip18:fsq-snapshot-acquire` — preview by default; execute requires `--execute`,
  `CONFIRM_CONFLUENDO_FSQ_SNAPSHOT_ACQUIRE=YES`, token from env, and
  `--artifact-store-dir` outside the git worktree.

Acquisition vs activation:

- **Acquisition** — fetch/normalize provider export, validate via IP-18.8.9 intake,
  store immutable artifacts, optionally register `activation_ready` metadata.
- **Activation** — later slice only: bind the registered release into the bundled
  consumer contract and re-seed `vamo-eu-full-data-v1` supply.

### IP-18.8.9 — implemented (versioned snapshot intake)

**Status:** done — repeatable local intake for reviewed FSQ OS Places exports.
**Not** live provider calls, **not** queue reseed, **not** snapshot activation,
**not** console UI.

Deliverables:

- `snapshot-release-manifest.ts` — versioned release manifest parser recording
  source key/provider, release id, acquired-at, provenance URL, attribution,
  license, fact-storage approval, retention statement, expected SHA-256, source
  format, and intended consumer/target.
- `versioned-snapshot-intake.ts` — pure local intake helper that verifies input
  SHA-256, validates Vamo candidate facts/attribution, rejects media bytes and
  unknown fields, emits deterministic normalized JSONL plus coverage by country
  and POI type from valid rows only.
- `ip18:snapshot-intake` — preview by default; `--execute` requires
  `CONFIRM_CONFLUENDO_SNAPSHOT_INTAKE=YES`, explicit `--manifest`, `--input`,
  and a new `--output-dir`, refuses git-worktree output paths and replacement
  of an existing release, atomically writes `source.jsonl`, `release.json`,
  and `coverage-report.json`.
- Intake vs activation documented: operators may still run manual IP-18.8.9
  intake for reviewed exports, but hosted autonomy should consume registered
  acquisition artifacts from IP-18.8.10 instead of calling FSQ directly.
  Activation/reseed remains a later reviewed slice. Never commit the export or
  token.

### IP-18.8.4 — implemented (production package batch controls)

**Status:** done — operator-controlled multi-unit production package approval,
existing delivery handoff for multi-item waves, and batch Apply-to-Vamo via the
existing least-privilege apply adapter. **Not** autonomous production delivery,
**not** autonomous consumer apply, **not** provider calls.

Deliverables:

- Explicit `unitKeys` on production package approval with per-unit rejection
  reasons; greedy fallback unchanged when omitted.
- Delivery tab selectable queue with filters, selection summary, and
  `Approve selected package wave` (defaults 5/5/10 after prior delivery).
- `POST /api/admin/ingestion/production-package-wave/apply-wave` plus batch
  preflight; sequential per-package apply with stop-on-first-failure.

### IP-18.8.7 — implemented (production handoff policy control)

**Status:** done — admin-console control for enabling or disabling autonomous
production package approval/delivery inside the active autonomy policy. **Not**
a general policy editor, **not** autonomous Apply to Vamo, **not** a production
inbox writer path.

Deliverables:

- `ingestion_platform.set_autonomy_production_handoff(...)` security-definer
  function owns the policy mutation, audit row, event row, optimistic
  concurrency, and allowed-transition update.
- `/admin/ingestion` Agent tab exposes a Production package handoff card with
  audit reason, fixed target-state confirmation, admin/AAL2/fresh-step-up
  gating for enable, and immediate audited disable.
- Enabling sets `production_inbox_handoff_policy.enabled=true`,
  `requiresIp18_6=false`, and `consumerApplyEnabled=false`, then adds only
  `approve_production_package_wave` and `deliver_production_package_wave`.
- Disabling removes those two transitions and keeps Apply to Vamo
  operator-controlled.
- Bootstrap grants `confluendo_app` `EXECUTE` on the function only; no direct
  `UPDATE` on `ingestion_autonomy_policies`.

### IP-18.8.8 — implemented (cross-plan lifecycle resolution)

**Status:** done — the queue and Delivery views now resolve an effective
operator lifecycle across prior plans for the same project, target, and scope.
**Not** a queue-status mutation, policy change, delivery path, or schema
change.

Deliverables:

- Read-only production package history is resolved by `unit_key` across prior
  plans for the same target and attached only to the live queue snapshot.
- Queue displays the effective lifecycle such as `Already applied in a previous
  plan`, while the plan-local stage remains available as technical evidence.
- Delivery filters and package selection treat prior-plan package states as
  effective delivery states; applied scopes are not selectable.
- Existing server-side occupied-unit enforcement remains authoritative.

### IP-18.8.3 — implemented (explicit batch plan selection for autonomy drain)

**Status:** done — autonomy drain and dashboard reads pin an explicit batch plan
key from policy summary (`batchPlanKey`) or hosted scheduler env/CLI override.
**Not** live provider ingestion, **not** Vamo target writes.

Deliverables:

- `batch-plan-selection.ts` — pure resolver for autonomy drain plan key
  (override → policy field → policy summary aliases).
- `loadBatchQueueSnapshot()` accepts optional `planKey` filter instead of
  always picking the latest updated active plan.
- Autonomy executor, dashboard read, hosted scheduler env
  (`CONFLUENDO_AUTONOMY_SCHEDULER_BATCH_PLAN_KEY`), and
  `ip18:autonomy-scheduler --batch-plan-key` pass the resolved key through.
- Full-data CLI wording: blueprint counts labeled before source binding;
  seed preview labeled operational queue preview; parked empty scopes use
  operator-friendly copy instead of “Resolve N blocked units”.

Operator note: set `summary.batchPlanKey` on the autonomy policy (for example
`vamo-eu-full-data-v1`) so drain does not follow whichever plan was most
recently re-seeded. Apply/verify from the Confluendo control DB owner console:

```sql
update ingestion_platform.ingestion_autonomy_policies ap
set summary = jsonb_set(
      coalesce(ap.summary, '{}'::jsonb),
      '{batchPlanKey}',
      to_jsonb('vamo-eu-full-data-v1'::text),
      true
    ),
    updated_at = now()
from ingestion_platform.ingestion_projects p
where p.id = ap.project_id
  and p.project_key = 'vamo'
  and ap.policy_key = 'vamo-eu-poi-staging-v1'
returning
  ap.policy_key,
  ap.policy_version,
  ap.summary->>'batchPlanKey' as batch_plan_key;
```

Verification:

```sql
select
  ap.policy_key,
  ap.status,
  ap.summary->>'batchPlanKey' as batch_plan_key
from ingestion_platform.ingestion_autonomy_policies ap
join ingestion_platform.ingestion_projects p on p.id = ap.project_id
where p.project_key = 'vamo'
  and ap.policy_key = 'vamo-eu-poi-staging-v1';
```

For one-off execution without changing policy summary, pass
`--batch-plan-key vamo-eu-full-data-v1` to `ip18:autonomy-cycle` or
`ip18:autonomy-scheduler`.

### IP-18.8.2 — implemented (supply-ready proposal binding)

**Status:** done — bounded dry-run schedule proposals for supply-ready
full-data units, persisted proposal JSON in control-plane seed, stale-proposal
clearing on re-seed. **Not** live provider ingestion, **not** Vamo target writes.

Deliverables:

- `batch-supply-ready-proposal-binding.ts` — attaches `ScheduleProposal` only to
  `supply_ready` units; row limits bounded by valid local snapshot rows (not
  `volumeProjection`).
- Optional `dryRunProposalFacts` in batch spec + bundled full-data YAML section.
- Queue persistence/seed writes proposal JSON for ready units; re-seed clears
  proposals when units become empty/invalid.
- Default full-data preview/seed: **36** `ready_for_dry_run`, **132** parked
  empty scopes, **38** local snapshot rows.

Plan selection / autonomy: set `summary.batchPlanKey` on the autonomy policy
(or pass `--batch-plan-key` / `CONFLUENDO_AUTONOMY_SCHEDULER_BATCH_PLAN_KEY`
for an explicit run override) to pin which active batch plan autonomy loads.
Without an explicit key, queue reads still fall back to the latest updated
active plan for the project/target.

### IP-18.8.1 — implemented (Vamo full-data snapshot supply binding)

**Status:** done — per-unit snapshot supply read model, default full-data seed
blocking for empty units, CLI supply previews. **Not** live provider ingestion,
**not** Vamo staging/production writes, **not** consumer apply.

Deliverables:

- `batch-snapshot-supply-preview.ts` — pure per-unit supply states
  (`supply_ready`, `supply_empty`, `supply_invalid`), row counts, operator
  labels, and default seed mode `block_empty_units` with blocker
  `source_snapshot_empty`.
- Queue seed path applies supply binding when a local `snapshotPath` is declared;
  default full-data seed **blocks** 132 empty units instead of marking them
  dry-run-ready. Opt-in `--include-empty-units` preserves unblocked rows.
- CLI previews show supply-ready vs empty units, rows by country/POI type, and
  default seed behavior (write-free preview).

Operator path:

1. Preview plan + projected volume (`ip18:batch-plan -- --full-data`).
2. Preview supply coverage + seed behavior
   (`ip18:batch-queue-seed -- --full-data --preview`).
3. Decide whether current snapshot supply is sufficient.
4. Seed control queue with default empty-unit blocking when approved.
5. A follow-up slice attaches/approves dry-run proposals for supply-ready units
   so hosted autonomy can drain them inside policy bounds.

### IP-18.8.0 — implemented (Vamo full-data queue plan foundation)

**Status:** done — contract/fixture-driven full-data batch plan, pure preview
read model, CLI `--full-data` / `--preview` extensions. **Not** live provider
ingestion, **not** Vamo staging/production writes, **not** consumer apply.

Deliverables:

- `fixtures/platform/ip18/vamo-eu-full-data-batch.yaml` — expanded EU geography
  × POI category matrix with snapshot source metadata, consumer contract ref,
  and per-category volume projection (source candidates vs expected target writes).
- `batch-plan-spec.ts` — optional `consumerContractRef`, `source`, and
  `volumeProjection`; rejects URL/live/evasion source controls.
- `batch-full-data-plan-preview.ts` — pure preview summarizing queue unit count,
  coverage matrix, projected volume totals, actual local snapshot supply, and
  consumer-contract POI display labels.
- CLI:
  - `ip18:batch-plan -- --full-data` — preview expanded plan (writes nothing).
  - `ip18:batch-queue-seed -- --full-data --preview` — queue preview only.
  - `ip18:batch-queue-seed -- --spec ...` — explicit control-plane seed path when
    approved (`CONFIRM_CONFLUENDO_BATCH_QUEUE_SEED=YES` + control DSN for execute).

Operator path:

1. Preview expanded plan, projected volume, and actual snapshot supply evidence
   (`ip18:batch-plan -- --full-data`).
2. Preview queue units plus actual snapshot supply
   (`ip18:batch-queue-seed -- --full-data --preview`).
3. When approved, seed the control-plane queue (SQL file or `--execute`).
4. Hosted autonomy (IP-18.7.5) drains eligible units inside stored policy bounds.

Validation: `@confluendo/ingestion-platform` tests + `ip15:boundary-audit`;
console/site build unchanged except read-model exports.

Previously planned IP-18.7.1 items (now landed):

- Define the stored autonomy policy for a source/target pair: allowed sources,
  geographies, categories, environments, max units, max rows, rolling limits,
  drift/blocker thresholds, and production-inbox handoff rules.
- Define an autonomy run ledger that records selected units, phase, bounds,
  stop reason, and linked dry-run/wave/package evidence.
- Define the agent-as-operator contract: agent identity, telemetry requirements,
  diagnosis payloads, and which corrective actions may run without a human.
- Name the first control-plane objects: `ingestion_autonomy_policies` for the
  human-approved source/target envelope and `ingestion_autonomy_runs` for the
  append-only cycle ledger.
- Extend the actor model with `autonomous_agent`, whose authority is limited to
  the active policy envelope, existing guards, and idempotent ledger state.
- Add the deterministic pure policy seam:
  `autonomy-policy.ts::evaluateAutonomyCycle()`, reusing existing dry-run,
  staging-canary, and production-inbox policy decisions.
- Define `autonomy.cycle.*` and `autonomy.action.*` telemetry events plus audit
  rows linking policy, run, unit, blocker, shipment/package, and corrective
  action evidence.
- Define when the orchestrator may continue unattended and when it must pause
  for operator review.

Operational commissioning can continue in parallel with small, explicit staging
waves if needed, but new implementation work should move toward policy-driven
autonomy.

Operationally, IP-17 proved the production inbox path at tiny scale. IP-18
automates the planning surface so broad EU city/POI coverage no longer depends
on one-off manual target creation. IP-18.5 adds governed batch staging canaries
on top of the IP-16 per-unit adapter; IP-18.7 turns those proven steps into a
bounded autonomous control loop.
