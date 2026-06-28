# IP-16 — First Vamo Staging Canary Runbook

This runbook describes the **manual, separately approved** procedure for
promoting one reviewed dry run to a tiny, bounded, reversible write into **Vamo
staging only**. It is the live execution arm of the IP-16 slice. Design and
invariants live in `STAGING_CANARY.md`; this document is the operational
checklist.

> Production shipment is blocked: proposals may name `production_write` only so
> policy can reject it, while durable target/shipment write modes and the target
> adapter permit only an approved staging canary.

## Preconditions

1. The target is at `review_required` with a **compatible** shipment diff and
   `wroteToTarget === false` (verify in the ingestion dashboard, IP-14 board).
2. A dashboard approval has been recorded for the target
   (`approve_staging_canary` in `ingestion_audit_log`) by an `ingestion_admin`
   with a verified AAL2 MFA factor, a fresh step-up, and a non-empty audit
   reason. See the staging-canary control on `/admin/ingestion`.
3. You have a **staging** Postgres DSN. Never a production DSN.
4. The target database has a positive sentinel:
   `ingestion.environment = 'staging'`. Absence of this setting blocks the
   write. See **Provisioning the staging sentinel** below.
5. You have an explicit green light to perform a live staging write.

## Provisioning the staging sentinel (DBA, out-of-band)

The adapter's "prove staging" check reads a database-level setting and fails
closed if it is missing. This setting is the durable proof that a connection is
actually a staging database; it must be provisioned **out-of-band by a DBA or
operator on the Vamo staging database only**, never by ingestion code.

Run once, against the **Vamo staging** database, as a DBA:

```sql
ALTER DATABASE <vamo_staging_db_name> SET ingestion.environment = 'staging';
```

New sessions then report `current_setting('ingestion.environment') = 'staging'`,
which is what the adapter requires before it will write.

Rules — these are load-bearing for the whole staging guarantee:

- **Ingestion code must never set this sentinel.** The platform must not run
  `SET ingestion.environment = …`, `set_config('ingestion.environment', …)`, or
  any session/transaction-scoped assignment. If the code under test could set
  its own proof, the proof would be self-asserted and worthless. The adapter
  only ever *reads* `current_setting('ingestion.environment')`.
- **Production must never carry this sentinel set to `staging`.** Do not run the
  `ALTER DATABASE … SET ingestion.environment = 'staging'` statement on a
  production (or production-like) database. A production database must have the
  setting unset (or set to a non-`staging` value), so the adapter fails closed
  there even if a wrong DSN is supplied by mistake.
- The setting is database-scoped and persists across sessions; verify with
  `SHOW ingestion.environment;` on a fresh staging session before a canary.

## Dry preview (safe, CI-runnable)

Always preview first. With no environment and no flag, the CLI prints the
bounded plan and the gate status, then **hard-fails (exit 1) without writing**:

```bash
npm --workspace @vamo/ingestion-platform run ip16:staging-canary
```

Expected: a printed plan (environment `staging`, `staging_write -> approved_write`,
write count within bound), confirmation that the reviewed dry run is eligible
for operator approval, then a `NO WRITE PERFORMED` gate summary and a non-zero
exit. This is the expected, safe outcome.

## Live staging canary (manual, gated)

Only after the preconditions and an explicit green light. Every gate below is
mandatory; a missing gate hard-fails with no write.

```bash
CONFIRM_VAMO_STAGING_CANARY=YES \
VAMO_STAGING_CANARY_ENVIRONMENT=staging \
VAMO_STAGING_DATABASE_URL="postgres://…staging…" \
VAMO_STAGING_CANARY_APPROVAL_ID="<approve_staging_canary audit id>" \
INGESTION_CONTROL_DATABASE_URL="postgres://…confluendo-control…" \
VAMO_STAGING_CANARY_REASON="<the approved audit reason>" \
node scripts/run-ip16-staging-canary.mjs --execute
```

Gates enforced, in order:

1. `CONFIRM_VAMO_STAGING_CANARY=YES` — explicit human confirmation.
2. `VAMO_STAGING_DATABASE_URL` — the staging DSN must be present.
3. `VAMO_STAGING_CANARY_ENVIRONMENT=staging` — anything else (notably
   `production`) is refused.
4. `--execute` — without it, the CLI previews and stops.
5. `VAMO_STAGING_CANARY_APPROVAL_ID` — the accepted dashboard approval audit
   row to bind this run to.
6. `INGESTION_CONTROL_DATABASE_URL` — used to verify the approval and record
   the shipment ledger.
7. **Approval TTL** — the recorded approval's `created_at` must be within a
   bounded window (default **15 minutes**). A stale or future-dated approval is
   refused before any write. Override the window only when justified, via
   `VAMO_STAGING_CANARY_APPROVAL_MAX_AGE_MINUTES` (a positive integer of
   minutes).
8. **Single-use** — before touching the target, the CLI checks the Confluendo
   control DB for an existing shipment tied to this approval id (shipment key
   `staging-canary:<targetId>:approval:<approvalId>`). If a
   `succeeded`/`shipping`/`approved` shipment already exists, the run refuses.
   One recorded approval ships at most once; record a fresh approval for another
   run.
9. The target adapter independently **proves staging**: it refuses unless the
   target DB reports `current_setting('ingestion.environment') = 'staging'`.
   The CLI also refuses if the operator environment is not `staging` or if the
   DSN matches the production host pattern (`VAMO_PRODUCTION_HOST_PATTERN`,
   default `prod`).

The write is bounded (`maxRows` 50 by default), idempotent (re-running is a
no-op), single-transaction, and refuses any diff that drifts from the recorded
approval or contains a `delete`. After a successful write, the CLI records a
control-plane shipment row, item rows, and a `ship_staging_canary` audit row
linked to the approval audit id. That ledger row is what makes the approval
single-use on any later invocation.

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

## Target write succeeded but control ledger failed

This is the one partial-failure window the design cannot make atomic: the staging
target write commits in the target DB, but the follow-up write to the Confluendo
control DB (shipment row + items + `ship_staging_canary` audit) then fails (e.g.
the control DB is briefly unreachable). The CLI detects this, prints a loud
`!!! TARGET WRITE SUCCEEDED BUT CONTROL LEDGER FAILED !!!` banner with the
`approval id`, `shipment_key`, written counts, and the per-item keys, and exits
non-zero.

Because the control ledger was not written, the **single-use guard cannot
protect a rerun** — a naive rerun could double-apply or mask the real state.
Operator procedure:

1. **Stop. Do not rerun the CLI**, and do not re-approve "to try again".
2. Capture the CLI output (the banner block has everything you need): the
   `approval id`, the `shipment_key`, the counts, and the canary item keys.
3. Inspect the **target** staging rows directly by those canary keys to confirm
   exactly what landed (the write is bounded and keyed, so this is small).
4. Reconcile the control plane to match reality, choosing one:
   - **Keep the rows**: manually record the shipment ledger so the approval is
     marked used — re-run only the ledger step (`recordStagingCanaryShipment`)
     with the captured counts/items, or insert the equivalent
     `ingestion_shipments` / `ingestion_shipment_items` / `ship_staging_canary`
     rows by hand. Verify the `shipment_key` matches the one in the banner.
   - **Undo the rows**: roll back using the captured items
     (`rollbackPostgresStagingCanary`), then record the rollback outcome in the
     audit log. The approval is then spent; record a fresh approval if you still
     want the canary.
5. Only once target and control are consistent (and the approval is recorded as
   used or explicitly retired) is the incident closed.

Do not treat a failed ledger write as "nothing happened." The target already
changed; treat it as a reconcile-by-hand event, not a retry.

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
