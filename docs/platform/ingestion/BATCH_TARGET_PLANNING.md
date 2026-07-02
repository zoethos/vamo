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

## CLI dry-run

```bash
npm --workspace @confluendo/ingestion-platform run ip18:batch-plan
npm --workspace @confluendo/ingestion-platform run ip18:batch-plan -- --spec path/to/batch.yaml
```

Prints plan id, unit counts, coverage summary, first N units, and next action.
Exits non-zero on validation failure or non-`dry_run` safety mode.

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

## Future slices

| Slice | Scope |
| --- | --- |
| IP-18.5 | Staged batch canary waves |
| IP-18.6 | Production inbox package waves |

## Safety

IP-18.0–18.4: planning and Confluendo control-plane queue persistence/scheduling/
execution only. No live ingestion, no provider calls, no Vamo staging or
production writes.
