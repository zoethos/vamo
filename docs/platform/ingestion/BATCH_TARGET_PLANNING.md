# Batch Target Planning (IP-18)

Consumer-neutral Confluendo batch planning expands a declared geography × category
matrix into deterministic dry-run target units. This slice is **planning only**:
no live scraping, no staging writes, no production inbox delivery, and no database
writes.

## Boundary

Confluendo owns the planner. Vamo is the first example consumer profile
(`vamo-place-intelligence`), not platform hard-coding. See
`CONFLUENDO_EXTRACTION_PREP.md` and `BUILD_SLICES.md` IP-15 for the extraction
boundary.

## Batch spec shape

Batch plans use `kind: ingestion.batch_plan` (YAML or JSON). Required fields:

| Field | Purpose |
| --- | --- |
| `projectKey` | Consumer project (e.g. `vamo`) |
| `sourceKey` | Dataset / source identifier |
| `targetProfileKey` | Target profile within the consumer |
| `targetKey` | **Environment-neutral** consumer target key |
| `targetEnvironment` | Explicit `staging` or `production` — never inferred from `targetKey` |
| `safetyMode` | IP-18 allows `dry_run` only |
| `geographies` | Countries, regions, cities, named areas, bounding boxes |
| `categories` | Category set to cross with geographies |
| `priorityHints` | Optional geography/category weighting |
| `bounds` | Optional `maxUnits`, `sampleRowLimitPerUnit`, `defaultBatchSize` |

Legacy environment-encoded keys such as `vamo-place-intelligence-staging` are
rejected. Unsafe modes (`staging_write`, `production_write`) fail validation.

## Planner behavior

`buildBatchPlan()` in `@confluendo/ingestion-platform/core`:

1. Expands geography × category into units with env-neutral `targetId`.
2. Deduplicates on `geography:category`.
3. Validates scope completeness; blocked units carry reasons.
4. Assigns deterministic run order (priority desc, then `unitKey` asc).
5. Optionally feeds each planned unit through existing `scoreTargetCandidate` +
   `buildScheduleProposal` when a scorecard template is supplied.

No DB, network, or provider calls.

## Vamo EU POI sample

`fixtures/platform/ip18/vamo-eu-poi-batch.yaml` is a small representative
fixture (Italy, France, Germany, Spain + a few cities/regions and categories
`poi`, `landmark`, `restaurant`, `transport`). It is **not** full EU coverage.
Later slices will source broad coverage from open snapshots (FSQ OS Places,
GeoNames, Wikidata, etc.).

## Vamo EU full-data plan (IP-18.8.0)

`fixtures/platform/ip18/vamo-eu-full-data-batch.yaml` expands the geography ×
category matrix to 12 EU countries with deterministic queue units at realistic
scale. The spec declares:

- snapshot `source.connection.snapshotPath` (local fixture only — no URLs);
- `consumerContractRef: vamo-place-intelligence` for queue display fields;
- `volumeProjection` per category distinguishing source candidates from expected
  target writes.

The projection is a planning estimate, not proof that those rows already exist
in the bundled snapshot. The preview commands also print actual local snapshot
supply when a `snapshotPath` is declared, including row count and planned units
with no matching snapshot rows.

This slice generates and previews queue units only. It does **not** ingest live
data or write to Vamo staging/production.

## Snapshot supply binding (IP-18.8.1)

IP-18.8.1 binds the full-data plan to the declared local snapshot file and makes
queue seeding honest about supply:

- bundled snapshot today: **38 rows** covering **36** of **168** planned units;
- **132** planned units have no matching local rows and are **blocked by default**
  during full-data seed with blocker `source_snapshot_empty`;
- supply-ready units remain in the queue but are not promoted to dry-run-ready
  unless they already have schedule proposals.

Pure helper: `batch-snapshot-supply-preview.ts::buildBatchSnapshotSupplyPreview()`.

Operator path:

1. Preview plan (`ip18:batch-plan -- --full-data`).
2. Preview supply coverage and default seed behavior
   (`ip18:batch-queue-seed -- --full-data --preview`).
3. Decide whether snapshot supply is sufficient for the next commissioning step.
4. Seed control queue when approved (default blocks empty units).
5. In the follow-up supply-to-schedule slice, attach/approve dry-run proposals
   for supply-ready units so hosted autonomy can drain them inside policy
   bounds. IP-18.8.1 itself only distinguishes supply-ready from empty units and
   blocks the known-empty rows by default.

Opt-in override: `--include-empty-units` on queue seed skips empty-unit blocking
(for planning review only; still control-plane only).

## Source acquisition and snapshot registry (IP-18.8.10 / IP-18.8.16 / IP-18.8.18)

IP-18.8.10 added the provider-facing acquisition boundary and control-plane
release registry. IP-18.8.16 replaces the fictitious catalog HTTP path with
Places Portal Iceberg acquisition via DuckDB. IP-18.8.18 makes that acquisition
category-aware so each requested country × Vamo POI type gets its own bounded
provider query. It is separate from activation and queue reseed:

- **Acquisition** — bounded FSQ OS Places Portal/Iceberg fetch through the
  dedicated adapter/job only; one query per requested country/type using
  explicit `sourceTaxonomy` provider IDs carried by `places_os`. The Portal
  catalog does not guarantee a separately queryable categories relation, so
  hierarchy expansion is an approved taxonomy-data change, never an implicit
  runtime guess. A configured POI type is queryable only through its explicit
  provider IDs; fallback remains non-evidence. The trusted job defaults to a
  five-minute query deadline; an operator may set the server-only
  `FSQ_OS_PLACES_PORTAL_QUERY_TIMEOUT_MS` from 30 seconds through 15 minutes.
  Classify after fetch; normalize deterministically by FSQ place id; reuse
  IP-18.8.9 intake; store immutable artifacts with
  `byCountryAndPoiType` from valid rows only; optionally register
  `activation_ready` metadata in the Confluendo control plane.
- **Activation** — IP-18.8.11: bind a registered release to a batch plan and
  reconcile `vamo-eu-full-data-v1` supply from the verified artifact (see below).

Boundary rules:

1. `FSQ_OS_PLACES_PORTAL_ACCESS_TOKEN` lives in server/job secrets only — never in
   console code, manifests, artifacts, logs, or tests.
2. Preview is write-free and credential-free.
3. Execute requires `--execute`, `CONFIRM_CONFLUENDO_FSQ_SNAPSHOT_ACQUIRE=YES`,
   plan `sourceTaxonomy`, and `--artifact-store-dir` outside the git worktree.
4. Console, scheduler, queue, dry-run, staging, delivery, and consumer apply
   paths must not call FSQ or import DuckDB.
5. On Windows runners set `NODE_USE_SYSTEM_CA=1` (documented job setup). Never
   set `NODE_TLS_REJECT_UNAUTHORIZED=0`.
6. IP-18.8.18 closes category starvation during acquisition, but sparse scopes
   may still return zero valid rows. Missing country/POI-type scopes are
   reported for operators and stay parked pending review or a later release —
   acquisition does not activate, reseed, or claim full EU coverage.
7. A plan with queue, staging, delivery, or consumer-apply history must not be
   reseeded only to add `sourceTaxonomy`: the seed path rewrites queue rows.
   Use the IP-18.8.17 audited metadata-only plan refresh control. It fills only
   a missing server-pinned published mapping, records audit/event evidence, and
   never replaces a mapping that already exists.

### Safe Plan Contract Refresh (IP-18.8.17)

The Queue-tab **Plan source mapping** card is the sole operator path for the
Vamo full-data plan catch-up. It is deliberately narrower than a plan editor:

- the server resolves the active policy/queue plan and supplies the published
  FSQ-to-Vamo taxonomy;
- the operator supplies only an audit reason and explicit confirmation under a
  fresh admin MFA step-up;
- the control-plane function changes only `spec.sourceTaxonomy`; it does not
  reseed units, alter their statuses/proposals/reports, or touch waves,
  deliveries, applied consumer data, or source-release bindings;
- a present or malformed mapping is treated as protected state and requires a
  separate governance change, not an automatic overwrite.

Apply the matching control schema and bootstrap grants to Control Staging,
verify the function-only app role path, then apply the identical pair to Control
Production in the same release window before using the action there.

Operator commands:

```bash
# Preview bounded scopes — writes nothing, token-free
npm --workspace @confluendo/ingestion-platform run ip18:fsq-snapshot-acquire -- \
  --countries italy,france --categories poi,landmark

# Execute after review (server/job secret store only)
CONFIRM_CONFLUENDO_FSQ_SNAPSHOT_ACQUIRE=YES \
FSQ_OS_PLACES_PORTAL_ACCESS_TOKEN=... \
INGESTION_CONTROL_DATABASE_URL=... \
npm --workspace @confluendo/ingestion-platform run ip18:fsq-snapshot-acquire -- \
  --execute \
  --countries italy,france \
  --categories poi,landmark \
  --artifact-store-dir /secure/confluendo-snapshot-artifacts
```

Artifact layout:

- immutable key: `{sourceKey}/{releaseId}/{outputSha256}`
- bundle files: `source.jsonl`, `release.json`, `coverage-report.json`
- registry status after successful registration: `activation_ready`

This slice does **not** activate a release, reseed the queue, or write to any
Vamo database.

## Snapshot release activation (IP-18.8.11)

IP-18.8.11 activates a verified `activation_ready` release into the
`vamo-eu-full-data-v1` batch plan without provider calls, Vamo writes, inbox
delivery, or consumer apply.

Control-plane binding:

- `ingestion_snapshot_release_plan_bindings` records one **active** binding per
  batch plan (not a global release status flip).
- `activate_snapshot_release(...)` is security-definer; `confluendo_app` may
  `SELECT` bindings and `EXECUTE` activation but cannot directly `UPDATE`
  registry or binding tables.

Trusted CLI:

```bash
# Preview — write-free; prints release/plan identity and queue reconciliation
npm --workspace @confluendo/ingestion-platform run ip18:snapshot-activate -- \
  --release-id fsq_os_places-20260701-deadbeefcafe \
  --plan-key vamo-eu-full-data-v1 \
  --artifact-store-dir /secure/confluendo-snapshot-artifacts \
  --audit-reason "Activate reviewed FSQ release for full-data queue."

# Execute after review
CONFIRM_CONFLUENDO_SNAPSHOT_RELEASE_ACTIVATION=YES \
INGESTION_CONTROL_DATABASE_URL=... \
npm --workspace @confluendo/ingestion-platform run ip18:snapshot-activate -- \
  --execute \
  --release-id fsq_os_places-20260701-deadbeefcafe \
  --plan-key vamo-eu-full-data-v1 \
  --artifact-store-dir /secure/confluendo-snapshot-artifacts \
  --audit-reason "Activate reviewed FSQ release for full-data queue."
```

Safety rules:

1. Artifacts resolve only beneath `--artifact-store-dir` / trusted store root;
   bundle SHA-256 and `outputSha256` must match registry metadata before any DB
   mutation.
2. Active-release plans **never** silently fall back to the bundled Vamo fixture
   for staging, approval, or production delivery candidate loading.
3. Reconciliation refreshes only source-reconcilable rows (`planned`,
   `ready_for_dry_run`, or `blocked` with `source_snapshot_empty` only). Terminal
   and in-flight evidence (`consumer_applied`, staging/production waves, dry-run
   reports) is preserved.
4. Console/browser read paths expose binding metadata only — never artifact URI,
   filesystem path, or control DSN.

Local limitation: trusted CLIs may still use `--artifact-store-dir` or
`INGESTION_ARTIFACT_STORE_DIR` on a trusted host. The hosted autonomy scheduler
requires S3-compatible artifact-store configuration and fails closed without it.

## Operator-confirmed activation requests (IP-18.8.14)

When a trusted commissioning worker has registered a release and its status is
`activation_pending`, Queue shows **Activate verified snapshot release**. The
operator supplies an audit reason, selects **Request activation**, and passes a
fresh MFA check. That action records an activation request only.

The browser neither reads the artifact nor calls the binding function. A trusted
job then runs:

```bash
CONFIRM_CONFLUENDO_SNAPSHOT_ACTIVATION_WORKER=YES \
INGESTION_CONTROL_DATABASE_URL=... \
npm --workspace @confluendo/ingestion-platform run ip18:snapshot-activation-worker
```

For Staging, the same worker is available as the manually dispatched
**Confluendo staging snapshot activation** GitHub Actions workflow. It claims
one already-recorded request using the protected
`confluendo-control-staging` environment and requires the hosted artifact
store. It has no FSQ Portal credential and cannot acquire provider data.
Production activation remains a separately commissioned managed-job concern.

The worker requires the same server/job-only artifact-store configuration as
the activation CLI. It claims one request, invokes the existing verified
activation path, and records `activated` or `failed`. It never acquires from a
provider. A failed request does not change the active binding; correct the
safe precondition and submit a new operator request.

Hosted artifact store (IP-18.8.15) — Supabase Storage operator setup:

The private `snapshot-artifacts` bucket already created in each Confluendo
Control Supabase project is the artifact store. It holds the verified
`source.jsonl`, `release.json`, and `coverage-report.json` bundle; the control
database stores only identity, checksum, and activation-binding metadata.

1. In **Storage → Configuration → S3** for each Confluendo Control project,
   enable S3 access and generate a distinct access-key pair. Save each secret
   at generation time; it cannot be shown again. Copy the exact S3 **region**
   displayed on that page; do not infer it from a project or bucket name.
2. Keep the environments in separate ignored files:
   - staging: copy [`web/.env.artifact-store.example`](../../../web/.env.artifact-store.example)
     into `Z:\vamo-ip17\web\.env.staging.local`;
   - production: copy [`web/.env.production.artifact-store.example`](../../../web/.env.production.artifact-store.example)
     into `Z:\vamo-ip17\web\.env.production.local`.
   Replace only the two placeholder key values in each file. They are separate
   from the Next app environment under `apps\confluendo-console`. Do not use a
   Supabase publishable key, service-role key, browser variable, Vamo
   environment, or a Git-tracked `.env` file.
3. Run the committed PowerShell wrapper below. It chooses the matching file,
   invokes the write-free preflight, then restores the shell's prior process
   environment.

```powershell
cd Z:\vamo-ip17\web
.\scripts\Test-ConfluendoSupabaseArtifactStore.ps1 `
  -ControlEnvironment Staging

# After the distinct production key exists:
.\scripts\Test-ConfluendoSupabaseArtifactStore.ps1 `
  -ControlEnvironment Production
```

The preflight uses `HeadBucket` only: it does not read or write a release. The
wrapper does not write keys to the user/machine environment.
Supabase S3 access keys are project-Storage credentials, so the trusted worker
is the only runtime allowed to hold them. Vamo has no artifact-store
credentials, and artifacts are never exposed via signed URLs, console props,
or API responses.

## Versioned snapshot intake (IP-18.8.9)

IP-18.8.9 adds a reviewed local intake path for approved FSQ OS Places exports.
It is separate from activation:

- **Intake** — validate a human-supplied normalized JSONL export against a
  versioned release manifest, verify SHA-256, reject media bytes and unknown
  fields, and write `source.jsonl`, `release.json`, and `coverage-report.json`
  outside the git worktree.
- **Activation** — later slice only: import/bind the accepted release into the
  bundled consumer contract and re-seed `vamo-eu-full-data-v1` supply.

Human-only prerequisite:

1. Obtain the FSQ export through the Places Portal using a separately stored
   source token.
2. Normalize it to the Vamo candidate JSONL shape locally.
3. Author a release manifest with the export SHA-256 and rights metadata.
4. Run intake preview, then execute outside the repo.

Never commit the export file or the provider token.

Operator commands:

```bash
# Preview only — writes nothing
npm --workspace @confluendo/ingestion-platform run ip18:snapshot-intake -- \
  --manifest /secure/manifest.yaml \
  --input /secure/fsq-export.jsonl \
  --output-dir /secure/vamo-snapshot-release

# Execute after review
CONFIRM_CONFLUENDO_SNAPSHOT_INTAKE=YES npm --workspace @confluendo/ingestion-platform run ip18:snapshot-intake -- \
  --execute \
  --manifest /secure/manifest.yaml \
  --input /secure/fsq-export.jsonl \
  --output-dir /secure/vamo-snapshot-release
```

This slice does **not** switch `vamo-eu-full-data-v1` to a new snapshot or
re-seed the queue. Coverage counts come from valid intake rows only, never from
planning projections.

`--output-dir` must name a **new**, empty release directory outside the git
worktree. Intake publishes the completed directory atomically and refuses to
replace an existing release.

### Source-rights approval record (2026-07-12)

Product/data owner approval for the bundled IP-18.8 Vamo full-data snapshot was
recorded on 2026-07-12 after verifying the declared source-rights facts and the
local snapshot evidence.

Verified evidence:

- plan source: local snapshot only,
  `fixtures/imported/vamo-place-intelligence/fixtures/source.jsonl`;
- declared proposal facts:
  `canStoreFacts=true`, `attributionPresent=true`,
  `retentionDeclared=true`, `liveOnly=false`;
- local snapshot rows: **38**;
- attribution: **38 / 38** rows carry `"FSQ Open Source Places"`;
- missing attribution rows: **0**;
- rows with `media.bytesBase64`: **1**.

Approval text:

> FSQ Open Source Places bundled snapshot may be used for fact storage in
> Confluendo/Vamo dry-run, staging verification, and production package
> preparation. Attribution required: `"FSQ Open Source Places"`. Retention:
> retain until superseded by a newer approved snapshot or until source rights
> change. Approval covers factual place data only; binary media bytes remain
> forbidden and must be blocked/ignored by policy.

This approval does **not** approve binary media storage. Rows containing binary
media bytes remain policy-invalid unless a future media-specific rights approval
is recorded.

## Supply-ready proposal binding (IP-18.8.2)

IP-18.8.2 attaches bounded dry-run `ScheduleProposal` objects to units with
verified local snapshot rows so they surface as `ready_for_dry_run`:

- proposal row limits use `min(spec row bound, validSourceRowCount)` — never
  `volumeProjection`;
- empty units stay `blocked` with `source_snapshot_empty`;
- invalid-only units stay `blocked` with `source_snapshot_invalid`;
- re-seed clears stale proposals when a unit loses snapshot supply.

Expected bundled preview/seed counts:

| Metric | Count |
| --- | ---: |
| Total queue units | 168 |
| Ready / proposal-backed | 36 |
| Blocked empty | 132 |
| Local snapshot rows | 38 |

After seed, `loadBatchQueueSnapshot()` returns the most recently updated active
plan. Autonomy drain-enablement is **not** automatic: confirm the seeded plan is
active and the autonomy policy envelope matches before enabling scheduler cycles.

## CLI dry-run

```bash
npm --workspace @confluendo/ingestion-platform run ip18:batch-plan
npm --workspace @confluendo/ingestion-platform run ip18:batch-plan -- --spec path/to/batch.yaml
npm --workspace @confluendo/ingestion-platform run ip18:batch-plan -- --full-data
```

Prints plan id, unit counts, coverage summary, projected volume (when declared),
actual local snapshot supply (when a snapshot path is declared), first N units,
and next action. Exits non-zero on validation failure or non-`dry_run` safety
mode.

## Full-data queue preview and seed (IP-18.8.0 / IP-18.8.1)

```bash
# Preview queue units, volume totals, and snapshot supply — writes nothing
npm --workspace @confluendo/ingestion-platform run ip18:batch-queue-seed -- --full-data --preview

# Write control-plane seed SQL when approved (blocks empty units by default)
npm --workspace @confluendo/ingestion-platform run ip18:batch-queue-seed -- --full-data

# Opt-in: include empty units without source_snapshot_empty blocking
npm --workspace @confluendo/ingestion-platform run ip18:batch-queue-seed -- --full-data --include-empty-units

# Optional: any valid batch spec
npm --workspace @confluendo/ingestion-platform run ip18:batch-queue-seed -- --spec path/to/batch.yaml --preview
```

Execution to the control DB requires `CONFIRM_CONFLUENDO_BATCH_QUEUE_SEED=YES`
and `INGESTION_CONTROL_DATABASE_URL`. No Vamo target writes occur in this path.

## Dashboard preview

`/admin/ingestion` includes a read-only **IP-18 batch planning preview** panel
fed from bundled sample read-model data. No write or approval controls in this
slice.

## Dashboard queue (IP-18.1)

`buildBatchQueueSnapshot()` turns a batch plan into operational queue state for
the console:

- **BatchQueueSnapshot** — plan metadata, progress counters, coverage, groups,
  items, blocker summaries, next action.
- **BatchQueueGroup** — country-grouped units with per-group progress.
- **BatchQueueItem** — unit queue row with explicit `targetEnvironment` metadata.
- **Statuses** — `planned`, `blocked`, `ready_for_dry_run`, `dry_run_ready`,
  `staged_ready`, `production_ready`, `applied`.

The Vamo EU POI sample feeds the first bundled queue fixture. Units with
schedule proposals surface as `ready_for_dry_run`; blocked units aggregate
reasons into blocker summaries. Optional per-unit progression overrides support
future persistence without changing the read-model shape.

The console **Batch Queue** section shows coverage cards, a country/category
matrix, blocker summaries when present, and the full queue table. Read-only: no
mutation buttons, no start-ingestion control, no staging/production write paths.

## Persistent queue (IP-18.2)

Control-plane tables under `ingestion_platform`:

- **`ingestion_batch_plans`** — plan metadata, spec JSONB, summary JSONB, explicit
  `target_environment`, env-neutral `target_key`, `safety_mode = dry_run`.
- **`ingestion_batch_queue_items`** — one row per queue unit with CHECK-constrained
  statuses matching IP-18.1.

Persistence path:

1. `mapSnapshotToPersistenceBundle()` — pure mapper from `BatchQueueSnapshot`.
2. `persistBatchQueueSnapshot()` — idempotent upsert into control tables only.
3. `loadBatchQueueSnapshot()` — live read back into `BatchQueueSnapshot`; returns
   `null` when tables are absent so the console falls back to sample data.

Seed/bootstrap:

```bash
npm --workspace @confluendo/ingestion-platform run ip18:batch-queue-seed
```

Writes `docs/platform/ingestion/bootstrap/sql/ip18_vamo_batch_queue_seed.sql`.
Execution mode requires `CONFIRM_CONFLUENDO_BATCH_QUEUE_SEED=YES` and
`INGESTION_CONTROL_DATABASE_URL`.

**Ops:** apply updated `control_schema.sql` to the live Confluendo control DB,
then run the seed SQL (or `--execute` mode) before expecting **Live control
plane** labels in `/admin/ingestion`. Without schema apply + seed, the dashboard
correctly shows **Sample preview**.

## Operator scheduling mutations (IP-18.3)

IP-18.3 adds the first state-writing operator action for the batch queue. The
scope is deliberately narrow:

- The dashboard can schedule eligible persisted queue rows from
  `ready_for_dry_run` to `dry_run_ready`.
- The route requires an authenticated Confluendo admin/operator session scoped
  to the project, AAL2 when MFA is required, same-origin JSON, and a non-empty
  audit reason.
- `evaluateBatchQueueScheduleDryRun()` is the pure policy decision; it has no DB
  or provider access.
- `scheduleBatchDryRun()` performs one Confluendo control-plane transaction:
  update eligible `ingestion_batch_queue_items` rows and record
  `schedule_batch_dry_run` in `ingestion_audit_log`.
- Live-read failures are surfaced as **Live read failed · sample fallback**
  instead of silently masquerading as sample preview; mutation controls are
  disabled in that state.

This action still does **not** execute ingestion. It creates queue state for the
next worker/dry-run slice; no provider calls, Vamo staging writes, or production
inbox delivery happen in IP-18.3.

**Ops:** after merge, re-run `control_bootstrap_confluendo.sql` on the live
Confluendo control DB so `confluendo_app` receives the queue-item `UPDATE` grant
needed by the scheduling route. Without that grant, the dashboard remains able to
read queue rows but scheduling fails closed with a permission error.

## Dry-run execution orchestration (IP-18.4)

IP-18.4 executes bounded dry-run work from persisted `dry_run_ready` queue units.
It writes only Confluendo control-plane state:

- `ingestion_batch_dry_run_executions` — idempotent execution ledger keyed by
  `(batch_plan_id, execution_key)`.
- Queue item transitions: `dry_run_running` → `dry_run_succeeded` or
  `dry_run_blocked`, with `run_report` JSONB and blockers.
- Audit action: `execute_batch_dry_run`.

Policy and simulator are pure modules:

- `evaluateBatchDryRunExecution()` selects eligible units with explicit
  `target_environment`, target key, max-units bound, and audit reason.
- `simulateBatchDryRunUnit()` produces deterministic fixture reports with
  `wroteToTarget: false` — no provider calls.

CLI:

```bash
npm --workspace @confluendo/ingestion-platform run ip18:batch-dry-run
cd web/packages/ingestion-platform
npm run build
CONFIRM_CONFLUENDO_BATCH_DRY_RUN=YES INGESTION_CONTROL_DATABASE_URL=... \
  node scripts/run-ip18-batch-dry-run.mjs --execute --max-units 2 --audit-id 15
```

Preview is the default mode. Execute requires `CONFIRM_CONFLUENDO_BATCH_DRY_RUN=YES`.
When running from PowerShell, prefer the direct `node scripts/run-ip18-batch-dry-run.mjs`
form for execute mode so npm does not treat forwarded flags as npm config.

**IP-18.3 live evidence:** audit id **15** scheduled 36 units to `dry_run_ready`
with explicit environment **staging** for target key `vamo-place-intelligence`.

**Ops:** after IP-18.4, re-run both `control_schema.sql` and
`control_bootstrap_confluendo.sql` on the live Confluendo control DB. The schema
adds `ingestion_batch_dry_run_executions` and extends the queue status check;
the bootstrap grants `confluendo_app` insert/update on the execution ledger and
update on queue `status`, `run_report`, `blockers`, and `updated_at`. Without
both, preview works but execute fails closed before any queue state is changed.
Before applying either SQL file, positively confirm the selected Supabase
project is the Confluendo control DB (`confluendo-control`, project ref
`agrcvzlkorlzwoxtkcft`). Role existence is not a database-proof because
Postgres roles are cluster-level.
IP-18.4 dry-run execution builds on that scheduled state without touching Vamo
targets.

**IP-18.4 live evidence:** after applying the updated live control schema and
bootstrap grants, the first bounded execution ran from the Confluendo control
DB with `CONFIRM_CONFLUENDO_BATCH_DRY_RUN=YES`:

- Execution key: `batch-dry-run:vamo-eu-poi-sample:audit:15`.
- Execution id: `1`; execution status: `succeeded`.
- Scheduling audit id: `15`; execution audit row: `16`.
- Units executed: 3.
- Queue after execution: 3 `dry_run_succeeded`, 33 `dry_run_ready`.
- Executed units:
  - `vamo-place-intelligence:rome-italy:poi`
  - `vamo-place-intelligence:paris-france:landmark`
  - `vamo-place-intelligence:barcelona-spain:landmark`
- Dashboard dry-run reports show `wroteToTarget=false`.

This proof wrote only Confluendo control-plane execution state and audit rows.
It did not call live providers and did not write to Vamo staging or production.

## Staged batch canary waves (IP-18.5)

See `STAGED_BATCH_CANARY_WAVES.md` for the full design and live evidence.
IP-18.5 is the first batch slice that may write to a consumer database again;
**production is forbidden** in IP-18.5.

Core rule: a staging canary **wave** is a bounded sequence of independent
**per-unit IP-16 staging canaries**. Each unit calls `applyPostgresStagingCanary`,
is sentinel-proven, atomic, individually ledgered, idempotent, and individually
rollback-able. No aggregate multi-unit direct write path.

Queue status extension (no production states):

```text
dry_run_succeeded -> staging_canary_ready -> staging_canary_approved
  -> staging_canary_running -> staging_canary_succeeded | staging_canary_blocked
```

Eligibility summary:

- Only `dry_run_succeeded` units with `run_report.wroteToTarget=false`.
- Explicit `target_environment='staging'` and `target_key='vamo-place-intelligence'`.
- Per unit: ≤ `STAGING_CANARY_MAX_ROWS` (50). Wave bounds: `maxUnits` + `maxTotalRows`.
- First live wave: hard-capped to **1 unit** in approval and execution; widening
  requires explicit new approval.

Approval reuses IP-16 semantics: admin + AAL2 + fresh MFA step-up + audit reason;
15-minute approval freshness (`STAGING_CANARY_APPROVAL_MAX_AGE_MS`); decision
writes only to Confluendo control DB.

Partial failure: **stop-on-first-failure** for the first implementation. Replay
skips already-succeeded units; per-unit idempotency via IP-16 shipment ledger.

Live baseline before IP-10.1: 3 `dry_run_succeeded` units from IP-18.4
execution key `batch-dry-run:vamo-eu-poi-sample:audit:15`; 33 units remained
`dry_run_ready` and were not staging-eligible until dry-run succeeded.

Implementation phases after IP-18.5.0: IP-18.5.1 (policy + schema), IP-18.5.2
(executor + smokes), IP-18.5.3 (dashboard + CLI), IP-18.5.4 (first live 1-unit wave).

Refreshed live evidence after IP-10.1:

- PR #133 landed bounded EU POI snapshot supply; PR #135 fixed dry-run
  target-row counting so candidate units report the two target rows they would
  write (`location_canonicals` + `location_source_refs`).
- IP-18.4 execution id **4** / audit id **33** prepared Paris landmark and
  Barcelona landmark with `insert_count=2`, `wroteToTarget=false`, and no
  blockers.
- IP-18.5 approval audit id **34** and execution audit id **36** shipped the
  Paris landmark unit to Vamo staging; shipment id **4** succeeded.
- Vamo staging verification found `fsq_paris_louvre_landmark` joined through
  `location_source_refs.canonical_id` to canonical
  `fsq-paris-louvre-landmark` (`Louvre Pyramid`, `feature_type='landmark'`).
- IP-18.5 approval audit id **37** and execution audit id **39** then shipped
  the Barcelona landmark unit to Vamo staging; shipment id **5** succeeded.
- Vamo staging verification found `fsq_barcelona_gothic_quarter_landmark`
  joined through `location_source_refs.canonical_id` to canonical
  `fsq-barcelona-gothic-quarter-landmark` (`Gothic Quarter`,
  `feature_type='landmark'`).
- No Vamo production write and no live provider call occurred.

## Future slices

| Slice | Scope |
| --- | --- |
| IP-18.5.x | Commissioning-only staging ramp over refreshed supply; do not make per-wave operator approval the steady-state workflow |
| IP-18.6 | Production inbox package waves for staging-proven units, reusing IP-17. Design source: `PRODUCTION_INBOX_PACKAGE_WAVES.md` |
| IP-18.7 | Autonomous batch orchestrator: source/target policy advances dry-run, staging, and production-inbox work inside approved bounds |

## Safety

IP-18.0–18.4: planning and Confluendo control-plane queue persistence/scheduling/
execution only. No live ingestion, no provider calls, no Vamo staging or
production writes.

IP-18.5: staging writes only via existing IP-16 adapter; production forbidden
until IP-18.6+.

IP-18.6: production inbox writes only via the existing IP-17 package builder and
Postgres production-inbox adapter. It delivers to the consumer inbox, not to
consumer product tables. Consumer apply remains consumer-owned and must be
tracked as separate telemetry.

IP-18.7 is the intended steady-state operating model. Operators approve source
and target policy bounds; Confluendo runs eligible batches autonomously and
pauses only on drift, blocker thresholds, missing target proof, write-limit
breaches, or policy widening.

**IP-18.7.1** (2026-07-06) adds the bounded control-plane executor loop:
one policy-evaluated action per cycle (`schedule_dry_run`, `execute_dry_run`, or
staging wave approval only). It does not execute live staging canary writes or
production inbox delivery (`waiting_for_ip18_6`).

**IP-18.6.1** (2026-07-07) adds production package-wave control-plane foundation:
queue statuses (`production_package_*`, `consumer_apply_*`), wave ledger tables,
pure eligibility/approval policy, and read model — no inbox delivery.
