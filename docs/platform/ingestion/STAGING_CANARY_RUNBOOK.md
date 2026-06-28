# IP-16 — First Vamo Staging Canary Runbook

This runbook describes the **manual, separately approved** procedure for
promoting one reviewed dry run to a tiny, bounded, reversible write into **Vamo
staging only**. It is the live execution arm of the IP-16 slice. Design and
invariants live in `STAGING_CANARY.md`; this document is the operational
checklist.

> Production is structurally impossible: there is no production safety mode,
> enum, environment, or adapter. Do not attempt to add one.

## Preconditions

1. The target is at `review_required` with a **compatible** shipment diff and
   `wroteToTarget === false` (verify in the ingestion dashboard, IP-14 board).
2. A dashboard approval has been recorded for the target
   (`approve_staging_canary` in `ingestion_audit_log`) by an `ingestion_admin`
   with a verified AAL2 MFA factor, a fresh step-up, and a non-empty audit
   reason. See the staging-canary control on `/admin/ingestion`.
3. You have a **staging** Postgres DSN. Never a production DSN.
4. You have an explicit green light to perform a live staging write.

## Dry preview (safe, CI-runnable)

Always preview first. With no environment and no flag, the CLI prints the
bounded plan and the gate status, then **hard-fails (exit 1) without writing**:

```bash
npm --workspace @vamo/ingestion-platform run ip16:staging-canary
```

Expected: a printed plan (environment `staging`, `staging_write -> approved_write`,
write count within bound), `Policy decision: APPROVED`, then a `NO WRITE
PERFORMED` gate summary and a non-zero exit. This is the expected, safe outcome.

## Live staging canary (manual, gated)

Only after the preconditions and an explicit green light. Every gate below is
mandatory; a missing gate hard-fails with no write.

```bash
CONFIRM_VAMO_STAGING_CANARY=YES \
VAMO_STAGING_CANARY_ENVIRONMENT=staging \
VAMO_STAGING_DATABASE_URL="postgres://…staging…" \
VAMO_STAGING_CANARY_REASON="<the approved audit reason>" \
VAMO_STAGING_CANARY_OPERATOR="<your id>" \
node scripts/run-ip16-staging-canary.mjs --execute
```

Gates enforced, in order:

1. `CONFIRM_VAMO_STAGING_CANARY=YES` — explicit human confirmation.
2. `VAMO_STAGING_DATABASE_URL` — the staging DSN must be present.
3. `VAMO_STAGING_CANARY_ENVIRONMENT=staging` — anything else (notably
   `production`) is refused.
4. `--execute` — without it, the CLI previews and stops.
5. The target adapter independently **proves staging**: it refuses if the
   environment env is not `staging`, if the DSN matches the production host
   pattern (`VAMO_PRODUCTION_HOST_PATTERN`, default `prod`), or if the database
   reports `current_setting('ingestion.environment') = 'production'`.

The write is bounded (`maxRows` 50 by default), idempotent (re-running is a
no-op), single-transaction, and refuses any diff that drifts from review or
contains a `delete`.

## Rollback

The apply path captures prior row state and returns per-item records
(`AppliedCanaryItem[]`) describing each insert/update with its keys and prior
state. Rollback removes inserted rows and restores updated rows to their
captured prior state, in one transaction, and is idempotent:

- Programmatic: `rollbackPostgresStagingCanary({ connectionString, items, proveStaging })`
  using the items returned by the apply (persist them from the run output).
- The rollback is also staging-gated and refuses a non-staging connection.

If anything looks wrong during or after the canary, roll back immediately, then
investigate from the shipment ledger, dead letters, and the audit log.

## Stop conditions

Stop and write nothing (or roll back if mid-flight) if any of these hold:

- the diff is incompatible or drifted from the reviewed diff,
- the write count exceeds the bound,
- the diff contains a `delete`,
- the connection cannot be proven to be staging,
- the approval/audit record is missing or stale,
- any error occurs during apply (the transaction rolls back automatically).

## After the canary

- Confirm row counts and spot-check the written rows in staging.
- Record the outcome (and the `AppliedCanaryItem[]` for rollback) alongside the
  approval audit entry.
- Do not widen scope, bounds, or environment without a new reviewed run and a
  new approval.
