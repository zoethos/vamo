# Ingestion Platform Build Slices

Status: implementation slicing record - updated 2026-06-28.

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

- `npm --workspace @vamo/ingestion-platform test -- spec` passes.
- `npm --workspace @vamo/ingestion-platform build` passes.
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

- `npm --workspace @vamo/ingestion-platform run import:contract -- --from <dir>` regenerates the snapshot.
- `npm --workspace @vamo/ingestion-platform test` passes.

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
transform exposed on its own package subpath (`@vamo/ingestion-platform/read-model`)
so the Next bundle never pulls `pg`/`node:fs` and there is no control-table or
service-role access in browser-reachable code. A live control API can later feed
the same transform real rows; only the snapshot source changes.

Files:

- `web/apps/site/app/admin/ingestion/page.tsx` (unchanged shell; label only)
- `web/apps/site/content/ingestion-dashboard.ts` (now reads through the read model)
- `web/packages/ingestion-platform/core/src/read-model.ts` (transform + view/domain
  types + sample control-plane snapshot)
- `web/packages/ingestion-platform/core/test/read-model.test.ts`
- `@vamo/ingestion-platform` added as a `@vamo/site` workspace dependency
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

- `web/apps/site/app/api/admin/ingestion/commands/route.ts`
- `web/apps/site/app/admin/ingestion/ingestion-command-controls.tsx`
- `web/apps/site/lib/ingestion-admin-auth.ts`
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

- `npm --workspace @vamo/ingestion-platform test`
- `npm --workspace @vamo/site run build`

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
- `npm --workspace @vamo/ingestion-platform test` runs with
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

- `npm --workspace @vamo/ingestion-platform test` - 114 pass, 2 DB smokes
  skipped without a database URL, 0 fail.
- `npm --workspace @vamo/ingestion-platform run ip14:dry-run` - exit 0,
  `dry_run`, no writes.
- `npm --workspace @vamo/site run build` - succeeds; `/admin/ingestion` renders.
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

Status: next (IP-14 merged).

Goal: prepare Confluendo to leave the Vamo incubation tree as an independent
repo, while making Vamo an importing consumer instead of the platform host.

IP-14 has landed and proves the real boundary:

```text
Vamo contract -> Confluendo import -> schedule/preflight -> dry-run -> dashboard review
```

Extracting before that would have risked moving scaffolding. Extracting after
staging or production writes risks letting Vamo-specific operational shortcuts
leak deeper into platform code, so do the split prep before the staging-canary
slice.

Architecture decision: provider repo plus consumer contracts. Confluendo owns
platform code, docs, auth templates, control SQL, worker runtime, adapters, and
admin surfaces. Vamo owns only its consumer contract, target credentials, product
schema, and integration notes.

Target Confluendo tree:

```text
confluendo/
  apps/
    console/
    control-api/
    worker/
  packages/
    core/
    spec/
    policy/
    adapters/
      source/
      target/
      transform/
    admin-ui/
    telemetry/
  examples/
    consumers/
      vamo-place-intelligence/
  docs/
    architecture/
    operations/
    auth/
  sql/
    control_schema.sql
    bootstrap_template.sql
```

Target Vamo tree:

```text
vamo/
  contracts/
    ingestion/
      vamo-place-intelligence/
        manifest.yaml
        pipeline.yaml
        target.yaml
        fixtures/
  docs/
    ingestion/
      vamo-confluendo-integration.md
  app/
  packages/
  supabase/
```

Allowed dependency direction:

- Vamo may depend on Confluendo packages, CLI, hosted APIs, embedded admin UI,
  and contract schemas.
- Confluendo must not depend on Vamo app code, Flutter packages, Vamo web
  routes, Vamo Supabase edge functions, or Vamo migrations.
- Confluendo may carry Vamo only as an example/imported consumer fixture with
  pinned provenance.

Split-prep tasks:

- Rename package identity from `@vamo/ingestion-platform` to a Confluendo-owned
  namespace.
- Move Vamo-specific imported fixtures into `examples/consumers/` or an explicit
  test fixture namespace.
- Convert `control_bootstrap_confluendo.sql` into a platform bootstrap template
  plus a Vamo example seed.
- Replace hard-coded `projectKey = "vamo"` defaults in platform-facing APIs with
  host-provided configuration.
- Keep Vamo-specific cache metrics in the Vamo host adapter, not platform core.
- Separate Confluendo auth/domain templates from Vamo auth/email templates.
- Ensure CI can run platform tests, site/console build, and disposable Postgres
  smoke without the Vamo repo.
- Define the Vamo import path: git path, package artifact, tarball, or CLI
  import command.

Acceptance criteria:

- A clean dependency scan shows no platform imports from Vamo runtime modules.
- The platform package, docs, and SQL are branded Confluendo, not Vamo.
- Vamo's contract bundle remains consumer-owned and can be imported into the
  platform from outside the platform repo.
- Vamo can still run its customer-zero dashboard/integration against the
  extracted Confluendo package/API.
- The new repo can run the ingestion-platform test suite with disposable
  Postgres.

## Slice IP-16 - First Vamo Staging Canary

Status: design spec documented; execution path not yet implemented.

Goal: promote exactly one reviewed dry run (a target at `review_required` with a
compatible diff and `wroteToTarget === false`) to a tiny, bounded, reversible
write into Vamo staging only. This is Confluendo's first write to a consumer
database; production stays structurally impossible.

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
- Hard production block at three layers: policy rejects `production_write`, the
  schema has no `production_write`/production enum, and no production adapter is
  wired.
- Approval requirement: `ingestion_admin` + fresh MFA step-up + audit reason +
  explicit `review_required -> staging_write` transition; machine tokens cannot
  promote.
- Canary bound: small row count (recommended `<= 50`), one geography, one
  category, idempotent upsert on declared keys, no `delete`, single shipment.
- Rollback: every written row is traceable by `shipment_id`/`run_id`; inserts
  are removable and updates are reversible via captured prior state; one audited
  operator action; idempotent.
- Telemetry: shipment ledger (`ingestion_shipments`/`_items`), checkpoint, dead
  letters, policy blocks, attribution, events, and audit log.
- Operator dashboard state transitions: `review_required ->
  staging_canary_pending -> staging_canary_shipped | staging_canary_blocked`,
  with `staging_canary_rolled_back`; no production node.
- Explicit stop conditions that always leave a no-write or fully-rolled-back
  state.
- Safety-mode mapping: policy `staging_write` + environment `staging` maps to an
  `approved_write` shipment; `production_write` has no durable representation.

Guardrails (carried from IP-14, unchanged):

- No production writes; no `production_write` enum widening.
- No live provider scraping, no VPN/proxy/evasion, no live AI calls (AI stays
  advisory per `TARGET_SELECTION_AND_SCHEDULING.md` §3).
- No service-role secrets, DSNs, or write credentials in browser code.
- No Vamo runtime coupling in platform core.

## What Not To Build Yet

- No real provider scraping.
- No Google reusable content cache.
- No production target writes.
- No autonomous AI-started ingestion without policy and operator approval.
- No connector marketplace.
- No standalone repo split until IP-15 split prep is complete (IP-14 has proven
  the dry-run loop).
- For IP-16, no "promote to production" control, no production environment/DSN,
  and no `production_write` enum value.

## Recommended Immediate Next Slice

**IP-14 - First Vamo Progressive Dry Run** has merged to `main` (PR #95, CI
green). The dry-run loop is proven end to end: Vamo contract -> Confluendo
import -> target scorecard -> preflight -> scout -> sample dry-run -> dashboard
review, with staging and production writes still disabled.

Run **IP-15 - Confluendo Repo Split Prep** (slice above) before any broad
staging canary or production shipment. The follow-on **IP-16 - First Vamo
Staging Canary** (spec at `docs/platform/ingestion/STAGING_CANARY.md`) then adds
the operator-driven promotion from `review_required` to `staging_write`, gated
by an `ingestion_admin` MFA step-up and an audit reason, mapped to a single
bounded, reversible `approved_write` shipment into Vamo staging only, with a
scheduling mutation endpoint (writing real `ingestion_schedule_proposals` rows)
as the supporting piece.
