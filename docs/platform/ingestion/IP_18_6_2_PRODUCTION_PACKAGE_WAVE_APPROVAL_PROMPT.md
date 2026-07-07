# IP-18.6.2 — Production Package-Wave Dashboard Approval

Implementation prompt. Build on IP-18.6.1. This slice adds the operator-facing
approval route/card for production package waves. It still does **not** deliver
anything to a consumer inbox.

## Context (read first)

- `docs/platform/ingestion/PRODUCTION_INBOX_PACKAGE_WAVES.md`
- `docs/platform/ingestion/IP_18_6_1_PRODUCTION_PACKAGE_WAVE_POLICY_PROMPT.md`
- `web/packages/ingestion-platform/core/src/batch-production-package-wave-policy.ts`
- `web/packages/ingestion-platform/core/src/batch-production-package-wave-control.ts`
- `web/apps/confluendo-console/app/api/admin/ingestion/batch-canary-wave/approve/route.ts`
- `web/apps/confluendo-console/app/admin/ingestion/batch-canary-wave-approval-control.tsx`
- `web/apps/confluendo-console/lib/ingestion-admin-auth.ts`

## Scope

Add a dashboard approval flow for production package waves:

- API route under `web/apps/confluendo-console/app/api/admin/ingestion/`.
- Client control/card under `web/apps/confluendo-console/app/admin/ingestion/`.
- Read-model wiring so the card sees eligible `staging_canary_succeeded` units,
  latest package-wave state, package progress, and blockers.
- Tests for route parsing/auth/policy blocks and happy path.
- Docs/runbook updates.

## Non-Goals

- No production inbox delivery CLI. That is IP-18.6.3.
- No `VAMO_PRODUCTION_INBOX_DATABASE_URL` use.
- No consumer apply or apply telemetry. That is IP-18.6.4.
- No autonomy production handoff. That is IP-18.6.5.
- No provider calls, Vamo staging writes, Vamo production writes, or consumer
  product-table writes.

## Critical Fix From IP-18.6.1 Review

Resolve the approval audit id duality before any delivery slice depends on it.

IP-18.6.1 can accept a caller-supplied `approvalAuditId`, build a wave key from
that value, then create a real `ingestion_audit_log` row and store that row id
as `approval_audit_id`. That is safe for the control-plane foundation, but it
must not become the production delivery identity model.

For IP-18.6.2:

1. The route must create or reserve the **real** `ingestion_audit_log` approval
   row first, inside the same transaction used to persist the wave.
2. Derive `waveKey` and every planned package key from that real audit id:
   `batch-production-inbox:{planKey}:wave:{realApprovalAuditId}:unit:{unitKey}`.
3. Persist the same real audit id in `approval_audit_id`.
4. Return that same real audit id to the browser.
5. Add a DB smoke proving:
   - `wave_key` contains the same id stored in `approval_audit_id`;
   - idempotent replay returns the same id;
   - a caller-supplied or stale id cannot create a different key/column pair.

Suggested implementation: refactor `approveBatchProductionPackageWave(...)` so
the control adapter owns audit creation and wave-key finalization. Do not make
the browser or route invent the durable package-wave id.

## Approval Route

Add route:

`web/apps/confluendo-console/app/api/admin/ingestion/production-package-wave/approve/route.ts`

Follow the staging wave approval route shape:

1. Parse JSON body:
   - `projectKey`
   - `targetKey`
   - `targetEnvironment` (must be `production`)
   - `schemaContract` (must be `vamo-place-intelligence@1`)
   - `maxUnits`
   - `maxRows`
   - `maxPackages`
   - `auditReason`
2. Use `authorizeStagingCanaryRequest` or an equivalently strict helper:
   same-origin JSON mutation, authenticated allowlisted admin, AAL2/fresh
   step-up surfaced through the pure policy.
3. Load the persisted batch queue snapshot via `loadBatchQueueSnapshot`.
4. Build `stagingEvidenceByUnitKey` from the latest succeeded staging-canary
   wave/item evidence already persisted in the control DB.
5. Build `occupiedUnitKeys` from active or spent production package wave items.
6. Call `evaluateProductionPackageWaveApproval`.
7. On block, return `409` with stable block codes.
8. On success, call the refactored persistence function that creates the real
   audit row, finalizes keys from that id, and persists the package wave.
9. Return `{ok, auditId, waveId, waveKey, unitKeys, idempotentReplay}`.

HTTP behavior:

- invalid body: `400`
- unauthenticated/unauthorized: existing admin JSON failure status
- no control DSN: `503`
- no queue: `404`
- policy block: `409`
- persistence failure: `500`

## Dashboard Card

Add a read/write client component modeled on
`batch-canary-wave-approval-control.tsx`.

The card should show:

- target key and explicit target environment `production`;
- eligible `staging_canary_succeeded` units;
- current package-wave progress block;
- latest production package wave, if present;
- schema contract `vamo-place-intelligence@1`;
- max units / max rows / max packages inputs;
- audit reason;
- clear copy: approval records a control-plane decision only; production inbox
  delivery is a separate confirmation-gated runbook step; consumer apply remains
  consumer-owned.

Default first Vamo approval:

- maxUnits = `1`
- maxPackages = `1`
- maxRows should be conservative and fit current evidence.

The card must distinguish:

- approved but not delivered;
- delivered to production inbox;
- consumer apply pending;
- consumer applied;
- consumer apply failed;
- blocked before delivery.

Do not resurrect the old ambiguity where failed apply looked like "already
delivered".

## Live Queue Re-Persist Ops Step

IP-18.6.1 fixed `mapQueueItemToPersistenceRow` so `dryRunReport` survives
persist/reload. Existing live rows persisted before that fix may still have
`run_report = null`, even when their status is `staging_canary_succeeded`.

Add this to docs and PR body:

- after applying IP-18.6.1 schema/bootstrap, re-persist or reseed the live batch
  queue from the current fixed code before testing IP-18.6.2 approvals;
- verify eligible staging-proven rows have non-null `run_report`;
- if `run_report` is missing, production package-wave approval must fail closed
  with dry-run evidence blocks.

Suggested read-only verification:

```sql
select unit_key, status, run_report is not null as has_run_report, blockers
from ingestion_platform.ingestion_batch_queue_items
where status in ('staging_canary_succeeded', 'production_package_approved')
order by run_order;
```

## Tests

Route tests:

- unauthenticated request fails;
- viewer/operator without admin role blocked by policy;
- AAL1/stale MFA blocked by policy;
- invalid `targetEnvironment` blocked;
- invalid `schemaContract` blocked;
- missing audit reason rejected;
- no queue returns `404`;
- happy path creates approval and returns real audit id;
- idempotent replay returns the same real audit id/wave key;
- route never touches `VAMO_PRODUCTION_INBOX_DATABASE_URL`.

DB/control tests:

- real audit id is created before/finalizes wave key;
- `approval_audit_id` equals the id embedded in `wave_key`;
- selected queue rows move to `production_package_approved`;
- unselected rows do not change;
- stale/caller-supplied fake audit id cannot create divergent keys;
- missing package-wave tables still degrade gracefully in read paths.

Component/read-model tests:

- eligible units count renders;
- block codes render;
- latest package wave renders with approval expiry;
- consumer apply failed is visually distinct from delivered/pending.

Validation gates:

- `npm --workspace @confluendo/ingestion-platform test` with disposable Postgres
  and DB smokes running;
- `npm --workspace @confluendo/ingestion-platform run ip15:boundary-audit`;
- `npm --workspace @confluendo/console run build`;
- `npm --workspace @vamo/site run build`;
- `git diff --check`.

## Safety Statement

Control-plane approval only. No provider calls. No Vamo staging writes. No Vamo
production writes. No production inbox delivery. No consumer apply. No browser
DB credentials. Production package delivery remains IP-18.6.3 and must reuse the
IP-17 production-inbox builder/adapter.

## Next Slice

After IP-18.6.2 lands, implement IP-18.6.3: confirmation-gated delivery CLI
that reuses the IP-17 package builder/adapter, checks approval freshness, and
performs the delivery-time drift recheck before any inbox write.
