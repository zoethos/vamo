# Ingestion Platform Build Slices

Status: implementation slicing draft - 2026-06-26.

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
- Keep the admin dashboard non-mutating until auth, control API, leases, audit
  logs, and target guards exist.

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

Goal: expose read-only run/target/event/status data to the admin page from the
platform model instead of hand-written static content.

Architecture decision: service boundary. Admin UI reads through an API/read
model; it does not read/write control tables directly.

Files:

- `web/apps/site/app/admin/ingestion/page.tsx`
- `web/apps/site/content/ingestion-dashboard.ts`
- `web/packages/ingestion-platform/core/src/read-model.ts`
- optional `web/apps/ingestion-control-api/`

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

Tests:

- Run-state transition matrix.
- Lease heartbeat timeout.
- Target-level pause.
- Reset blocked without reason.
- Audit event emission.

## Slice IP-08 - Containerized Worker Harness

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
- Validate PII firewall rules.
- Validate Google live-only policy.
- Produce a dry-run shipment diff for Vamo staging shape.

Acceptance criteria:

- Vamo profile can be validated by IP-01 spec parser.
- Vamo profile can run through fixture source adapter.
- Vamo profile produces a Postgres/Supabase dry-run plan.
- No cloud staging write until explicit green light.

## Slice IP-10 - First Real Open Dataset Source

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

## What Not To Build Yet

- No real provider scraping.
- No Google reusable content cache.
- No production target writes.
- No admin mutation controls in browser.
- No connector marketplace.
- No standalone repo split until the spec/core/adapter boundaries are proven.

## Recommended Immediate Next Slice

Start with **IP-01 - Spec Kernel And Fixture Contract**.

Reason: it is the smallest slice that creates real platform value without any
security, provider, or database blast radius. It also forces the YAML contract to
become executable before the UI and workers depend on it.

Once IP-01 is green, IP-02 and IP-03 can proceed in parallel:

- IP-02: database/control-plane schema.
- IP-03: no-network fixture ingestion and policy engine.

That gives us a spine: spec -> fixture source -> policy -> candidate output ->
checkpoint/events. Everything after that becomes wiring, adapters, and
operational hardening.
