# IP-18.6.1 — Production Package-Wave Policy and Schema

Implementation prompt. This is the first implementation slice under
[PRODUCTION_INBOX_PACKAGE_WAVES.md](./PRODUCTION_INBOX_PACKAGE_WAVES.md).

Deliver **control-plane foundation only**: schema, pure policy, persistence/read
model, and tests. Do **not** add dashboard approval, delivery execution, consumer
apply telemetry, provider calls, Vamo staging writes, or Vamo production writes.

## Context (read first)

- `docs/platform/ingestion/PRODUCTION_INBOX_PACKAGE_WAVES.md` — IP-18.6 design.
- `docs/platform/ingestion/PRODUCTION_INBOX_RUNBOOK.md` — proven IP-17 live
  production inbox flow and operational boundaries.
- `web/packages/ingestion-platform/core/src/production-inbox-policy.ts` —
  existing IP-17 pure policy and freshness constants.
- `web/packages/ingestion-platform/core/src/shipment-package.ts` —
  IP-17 package format and `schemaContract` shape.
- `web/packages/ingestion-platform/adapters/target/src/postgres-production-inbox.ts`
  — the only production inbox target adapter; future delivery must reuse it.
- `web/packages/ingestion-platform/core/src/batch-staging-canary-*` — closest
  precedent for wave policy, wave tables, idempotent persistence, and DB smokes.
- `web/packages/ingestion-platform/core/src/batch-queue-read-model.ts` and
  `batch-queue-control-read.ts` — queue statuses and dashboard read projection.
- `web/packages/ingestion-platform/core/sql/control_schema.sql` and
  `control_bootstrap_confluendo.sql` — control-plane DDL/grants.

## Why This Slice Exists

IP-17 proved a tiny production inbox package can be delivered and Vamo-owned
apply can succeed (`approval:13`, `applied=2`, `skipped=0`, `rejected=0`).
IP-18.5 proved staging-canary waves over real candidates. IP-18.6.1 creates the
missing control-plane layer that says which staging-proven units may become
production inbox package waves.

The key boundary remains:

- Confluendo may assemble and deliver packages to a consumer inbox.
- Confluendo must not write consumer product tables.
- Consumer apply remains consumer-owned and separately verified.

## Non-Goals

- No production inbox delivery CLI. That is IP-18.6.3.
- No dashboard approval route/card. That is IP-18.6.2.
- No consumer apply telemetry credential or polling. That is IP-18.6.4.
- No autonomy production handoff. That is IP-18.6.5.
- No new package format and no second production adapter.
- No JavaScript package checksum authority.
- No retry of spent package ids, especially package 10.

## Required Design Decisions

1. **Reuse IP-17 package contracts.** This slice may create package-wave plans
   and ledger rows, but future delivery must still call the existing IP-17
   builder/adapter path. Do not introduce a parallel package writer.
2. **Delivered is not applied.** Package delivery and consumer apply must be
   separate states in schema and read model.
3. **Approval freshness is explicit.** Reuse
   `PRODUCTION_INBOX_APPROVAL_MAX_AGE_MS` (15 minutes). The policy/read model
   must record `approval_expires_at`; execution slices must later block with
   `approval_expired`.
4. **Delivery-time drift recheck is required later.** This slice must persist
   enough approval evidence for IP-18.6.3 to recheck queue state, staging
   evidence, rows, checksum assumptions, and schema contract before any inbox
   write.
5. **Telemetry credential posture is explicit.** IP-18.6.4 must use a
   read-only, inbox-scoped consumer telemetry credential. Do not reuse the
   writer DSN for telemetry and do not require product-table reads.
6. **Schema contract compatibility has teeth.** Eligibility must assert the
   pinned Vamo package schema contract: `vamo-place-intelligence@1`.

## PR Scope

Branch `feature/ip18.6.1-production-package-wave-policy` from current
`origin/main`.

### 1. Queue Statuses

Update `web/packages/ingestion-platform/core/src/batch-queue-read-model.ts` and
the corresponding `ingestion_batch_queue_items.status` CHECK in
`control_schema.sql`.

Add explicit production package statuses:

- `production_package_ready`
- `production_package_approved`
- `production_package_delivering`
- `production_package_delivered`
- `consumer_apply_pending`
- `consumer_applied`
- `consumer_apply_failed`
- `production_package_blocked`

Do not collapse these into the older generic `production_ready` / `applied`
labels. Keep old statuses only if needed for backward compatibility.

Progress/read model should expose a `productionPackage` block with at least:

- ready
- approved
- delivering
- delivered
- applyPending
- applied
- applyFailed
- blocked

### 2. Control Schema

Add two control tables:

- `ingestion_platform.ingestion_batch_production_package_waves`
- `ingestion_platform.ingestion_batch_production_package_wave_items`

Update `CONTROL_TABLES` from **25 to 27**.

Minimum table requirements:

- `project_id` references `ingestion_projects`.
- `batch_plan_id` references `ingestion_batch_plans`.
- `wave_key` stable and unique per plan.
- `target_key` environment-neutral text.
- `target_environment text not null check (target_environment = 'production')`.
- `schema_contract text not null` with Vamo rows requiring
  `vamo-place-intelligence@1` through policy/tests.
- `approval_audit_id`, `approval_reason`, `approved_by`, `approved_at`,
  `approval_expires_at`.
- `status` CHECK with the production package wave states.
- `max_units`, `max_rows`, `max_packages` positive checks.
- package evidence fields: package id/key/checksum, delivery audit id,
  delivery status, consumer apply status/evidence.
- `blockers jsonb not null default '[]'::jsonb` with array check.
- `summary jsonb not null default '{}'::jsonb` with object check.
- timestamps.

Wave item minimum fields:

- `wave_id` references production package waves.
- `queue_item_id` references `ingestion_batch_queue_items`.
- `unit_key`, `run_order`, `planned_row_count`.
- `schema_contract`.
- `package_key` / `package_id` nullable until delivery.
- dry-run evidence and staging-canary evidence JSONB.
- status/checksum/apply evidence/blockers/timestamps.
- unique `(wave_id, unit_key)`.

Indexes:

- `(batch_plan_id, status, updated_at desc)` on waves.
- `(wave_id, status, run_order asc)` on items.
- `(project_id, target_key, target_environment, status)` where useful.

### 3. Bootstrap Grants

Update `control_bootstrap_confluendo.sql`:

- grant runtime read access through existing SELECT pattern;
- grant `insert, update` on the two new control tables to `confluendo_app`;
- grant sequence usage for any new identity sequences;
- no `DELETE`;
- no grants to consumer DBs or product tables.

DB smoke must prove:

- `confluendo_app` can insert/update waves and wave items;
- `confluendo_app` cannot delete them;
- sequence usage is present;
- no new grants touch Vamo/consumer product tables.

### 4. Pure Policy

Add a new pure helper, e.g.
`web/packages/ingestion-platform/core/src/batch-production-package-wave-policy.ts`.

Suggested exported functions:

- `evaluateProductionPackageWaveEligibility(...)`
- `evaluateProductionPackageWaveApproval(...)`
- `buildProductionPackageWaveKey(...)`

Eligibility requirements:

- queue item status is `staging_canary_succeeded`;
- target key is environment-neutral (`vamo-place-intelligence`, never the
  legacy `*-staging` key);
- package target environment is explicitly `production`;
- latest dry-run report exists and has `wroteToTarget === false`;
- latest staging-canary evidence exists and succeeded for the same unit;
- no active blockers;
- no deletes;
- write count is positive and within `maxRows`;
- `maxUnits`, `maxRows`, and `maxPackages` are bounded and positive;
- first live Vamo package wave is hard-capped at 1 unit / 1 package;
- package schema contract is exactly `vamo-place-intelligence@1`;
- the unit has not already been delivered in an active, pending-apply, applied,
  or failed-unresolved package.

Approval policy requirements:

- admin principal only;
- verified AAL2;
- fresh MFA step-up;
- non-empty audit reason;
- explicit production target environment;
- 15-minute `approval_expires_at` derived from
  `PRODUCTION_INBOX_APPROVAL_MAX_AGE_MS`;
- advisory warnings may be returned, but hard blocks above must fail closed.

Block codes must include at least:

- `not_staging_proven`
- `not_production_environment`
- `legacy_target_key`
- `schema_contract_mismatch`
- `dry_run_invariant_violated`
- `staging_canary_required`
- `staging_canary_not_succeeded`
- `active_blockers`
- `delete_not_allowed`
- `row_bound_exceeded`
- `unit_bound_exceeded`
- `package_bound_exceeded`
- `already_delivered_or_pending_apply`
- `approval_expired` (for loaded approved waves / future execution checks)
- `role_denied`
- `mfa_required`
- `fresh_step_up_required`
- `audit_reason_required`

### 5. Persistence and Read Model

Add control-plane persistence/read helpers, following the staging wave pattern:

- idempotent insert/upsert for package waves and package wave items;
- stable wave key using approval audit id:
  `batch-production-inbox:{planKey}:wave:{approvalAuditId}:unit:{unitKey}`;
- re-approval must mint a fresh key/id; never mutate spent package ids;
- load latest package wave into `BatchQueueSnapshot` separately from latest
  staging wave;
- missing-table fallback returns no package-wave state rather than crashing.

This slice may add an owner/test helper to persist a package-wave approval in
disposable Postgres, but do not add a live route or CLI.

### 6. Delivery-Time Drift Contract (Persist Evidence Now)

IP-18.6.3 must be able to fail closed before any production inbox write if the
world changed after approval. Persist enough evidence in the wave/item rows:

- queue item id and status at approval;
- unit key, geography, category, target key, target environment;
- dry-run execution key, row counts, write counts, and `wroteToTarget=false`;
- staging-canary shipment key/id/status/checksum evidence;
- schema contract;
- approved bounds;
- package key/package id planned for future delivery.

Add tests that mutate loaded evidence and prove the pure policy returns a drift
or incompatibility block. The actual delivery recheck is IP-18.6.3, but this
slice must not leave it impossible.

### 7. Apply-Telemetry Credential Note

Update docs in this slice to state:

- production delivery uses the existing writer DSN:
  `VAMO_PRODUCTION_INBOX_DATABASE_URL`;
- apply telemetry must use a separate read-only inbox-scoped credential in
  IP-18.6.4;
- that telemetry credential must not read consumer product tables and must not
  be exposed to the browser.

### 8. Tests

Pure tests:

- eligible staging-proven unit produces a package-wave approval plan;
- non-production environment blocked;
- legacy target key blocked;
- schema contract mismatch blocked;
- missing/failed staging evidence blocked;
- dry-run `wroteToTarget !== false` blocked;
- deletes blocked;
- active blockers blocked;
- unit/row/package bounds enforced;
- first wave over 1 unit blocked;
- already delivered / pending apply / applied / failed-unresolved blocked;
- admin+AAL2+fresh step-up required;
- approval expiry is 15 minutes and exposed.

DB smokes with disposable Postgres must RUN, not skip:

- schema applies and `CONTROL_TABLES` count is 27;
- grants work for `confluendo_app` insert/update and fail for delete;
- idempotent wave/item upsert creates stable rows and replay does not duplicate;
- queue rows move to `production_package_approved` only for selected units;
- read model reload preserves package-wave status, selected units, approval
  expiry, schema contract, and blockers;
- missing package-wave tables degrade gracefully to no package-wave state.

Regression tests:

- delivered vs consumer-applied states are distinct;
- `consumer_apply_failed` renders/loads as failed apply, not "already
  delivered";
- package key/id cannot be reused with incompatible checksum evidence.

### 9. Docs

Update:

- `PRODUCTION_INBOX_PACKAGE_WAVES.md` — mark IP-18.6.1 implemented when done
  and add the four hard implementation lessons: approval freshness,
  delivery-time drift recheck, read-only telemetry credential, schema contract
  pin.
- `BUILD_SLICES.md` — IP-18.6.1 status and next slice pointer to IP-18.6.2.
- `BATCH_TARGET_PLANNING.md` if the queue/status table needs a short status
  vocabulary update.
- `bootstrap/README.md` — note that live control DB must receive
  `control_schema.sql` and `control_bootstrap_confluendo.sql` before the
  dashboard/CLI can see package-wave state.

## Validation Gates

- `git diff --check`
- `npm --workspace @confluendo/ingestion-platform test` with disposable
  Postgres; DB smokes must run
- `npm --workspace @confluendo/ingestion-platform run ip15:boundary-audit`
- `npm --workspace @confluendo/console run build`
- `npm --workspace @vamo/site run build`

## PR Safety Statement

Control-plane only. No provider calls. No Vamo staging writes. No Vamo
production writes. No production inbox delivery. No consumer apply. No browser
DB credentials. Package wave state is approval/read-model infrastructure only;
future delivery remains confirmation-gated and must reuse the IP-17
production-inbox builder/adapter.

## Ops Note After Merge

Apply the updated `control_schema.sql` and `control_bootstrap_confluendo.sql` to
the live Confluendo control DB before expecting live package-wave data. Merge
alone must degrade gracefully when the live tables are missing.
