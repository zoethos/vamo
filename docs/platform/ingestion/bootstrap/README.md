# Confluendo Bootstrap Sequence

This folder is the operator bootstrap home for Confluendo-managed ingestion
instances. It captures the order needed to recover or provision the platform
without blurring the provider/customer boundary.

Confluendo owns the ingestion platform, control plane, admin auth, and
operator runbooks. Vamo is customer zero: its schema, seed rows, and staging
canary are documented here as a consumer instance of Confluendo, not as
platform-owned runtime code.

## Sequence

Run the phases in this order. Do not jump to a later phase because each one
proves a different trust boundary.

| Phase | Scope | Artifact | Owner | Writes To |
| --- | --- | --- | --- | --- |
| 1 | Confluendo control DB schema | `../../../../web/packages/ingestion-platform/core/sql/control_schema.sql` | Confluendo DBA | Confluendo control DB |
| 2 | Runtime role grants | `../../../../web/packages/ingestion-platform/core/sql/control_bootstrap_confluendo.sql` | Confluendo DBA | Confluendo control DB |
| 3 | Vamo live proposal seed | `sql/ip16_vamo_live_proposal_seed.sql` | Confluendo DBA | Confluendo control DB |
| 4 | Vamo target cache schema | `VAMO_CUSTOMER_ZERO_BOOTSTRAP.md` | Vamo DBA/operator | Vamo staging, then production schema-only |
| 5 | Vamo staging proof and canary role | `VAMO_CUSTOMER_ZERO_BOOTSTRAP.md` | Vamo DBA/operator | Vamo staging only |
| 6 | Dashboard approval | `../STAGING_CANARY_RUNBOOK.md` | Confluendo admin | Confluendo control DB audit |
| 7 | CLI dry preview | `../STAGING_CANARY_RUNBOOK.md` | Confluendo operator | No target writes |
| 8 | Live staging canary | `../STAGING_CANARY_RUNBOOK.md` | Confluendo operator | Vamo staging only |
| 9 | Vamo production inbox schema | `../../../../supabase/migrations/20260701100233_confluendo_inbox.sql` and `../../../../supabase/migrations/20260701121500_confluendo_inbox_writer_digest_usage.sql` | Vamo DBA/operator | Vamo production inbox schema |
| 10 | Vamo production inbox login | `../PRODUCTION_INBOX_RUNBOOK.md` | Vamo DBA/operator | Vamo production roles/grants |
| 11 | Production inbox approval | `../PRODUCTION_INBOX_RUNBOOK.md` | Confluendo admin | Confluendo control DB audit |
| 12 | Production inbox delivery | `../PRODUCTION_INBOX_RUNBOOK.md` | Confluendo operator | Vamo production `confluendo_inbox` only |
| 13 | Vamo product apply | `../PRODUCTION_INBOX_RUNBOOK.md` | Vamo DBA/operator | Vamo production product tables |
| 14 | Post-apply dashboard verification | `../PRODUCTION_INBOX_RUNBOOK.md` | Confluendo admin + Vamo operator | Read-only verification |

## Phase 2 Grant Checklist

After applying `control_schema.sql`, run
`../../../../web/packages/ingestion-platform/core/sql/control_bootstrap_confluendo.sql`
as the Confluendo control DB owner. That bootstrap must grant the runtime role
(`confluendo_app`) both read access for the dashboard and the narrow control
ledger writes used by IP-16:

```sql
grant usage on schema ingestion_platform to confluendo_app;
grant select on all tables in schema ingestion_platform to confluendo_app;

grant insert, update on ingestion_platform.ingestion_targets to confluendo_app;
grant insert, update on ingestion_platform.ingestion_shipments to confluendo_app;
grant insert, delete on ingestion_platform.ingestion_shipment_items to confluendo_app;

grant insert on ingestion_platform.ingestion_audit_log to confluendo_app;
grant usage, select on all sequences in schema ingestion_platform to confluendo_app;
```

These are Confluendo **control-plane** grants only. They do not grant
Confluendo any write access to Vamo production, and they do not replace the
separate Vamo staging `vamo_canary_app` role used for the bounded target write.

Verify the shipment-ledger grants before running a live canary:

```sql
select
  has_table_privilege('confluendo_app', 'ingestion_platform.ingestion_targets', 'SELECT, INSERT, UPDATE') as can_upsert_targets,
  has_table_privilege('confluendo_app', 'ingestion_platform.ingestion_shipments', 'SELECT, INSERT, UPDATE') as can_upsert_shipments,
  has_table_privilege('confluendo_app', 'ingestion_platform.ingestion_shipment_items', 'SELECT, INSERT, DELETE') as can_replace_shipment_items,
  has_table_privilege('confluendo_app', 'ingestion_platform.ingestion_audit_log', 'SELECT, INSERT') as can_record_audit;
```

Expected: all four values are `true`.

## Guardrails

- Never run a Vamo staging canary before phases 1-7 are green.
- Never set `CONFIRM_VAMO_STAGING_CANARY=YES` during bootstrap.
- Never run `--execute` during bootstrap verification.
- Never grant Confluendo write access to Vamo production.
- Never grant Confluendo direct write access to Vamo production product tables.
  Production delivery uses `confluendo_inbox` only; Vamo owns the apply step.
- Never create a production sentinel row with `value='staging'`.
- Never compute production inbox payload or package checksums in JavaScript.
  They must be computed by Vamo Postgres using `extensions.digest(...)`.
- Keep Confluendo control DB credentials separate from Vamo target DB
  credentials.
- Keep customer-specific seed artifacts in this bootstrap folder or a future
  consumer-package folder, not in generic platform runtime code.
- Do not retry spent package ids. If an old package failed because it was
  assembled by a superseded contract, record a fresh approval and deliver a new
  package after the fix is deployed.

## Current Vamo Customer-Zero Evidence

This bootstrap is no longer theoretical. The first production inbox proof has
completed at the tiny IP-17 scope:

| Package | Result | Notes |
| --- | --- | --- |
| `production-inbox:vamo-place-intelligence-staging:approval:10` | `consumer_apply_failed` | Historical failed package. It was delivered before IP-17.1 added `canonical_key` to source-ref payloads. Do not retry it. |
| `production-inbox:vamo-place-intelligence-staging:approval:13` | `consumer_applied` | Successful proof. Vamo applied 2 rows, skipped 0, rejected 0. `/admin/ingestion` shows the package as applied. |

This proves the governed pipe:

```text
Confluendo approval
  -> Confluendo production inbox delivery
  -> Vamo-owned apply function
  -> Vamo production product tables
  -> Confluendo dashboard read model shows applied
```

It does **not** prove broad EU POI coverage. That belongs to the later batch
planning/ingestion slices.

## Disaster Recovery Shape

For a fresh Confluendo instance serving Vamo:

1. Restore/apply the Confluendo control schema.
2. Bootstrap the Confluendo runtime role and the `vamo` project row.
3. Run the Vamo proposal seed in `sql/ip16_vamo_live_proposal_seed.sql`.
4. Apply Vamo's place-intelligence cache migration to Vamo staging and
   production as appropriate.
5. Provision the Vamo staging sentinel table and `vamo_canary_app` role.
6. Re-run read-only readiness checks before any approval or write.
7. Apply the Vamo production inbox migrations and provision a production login
   role granted `confluendo_inbox_writer`.
8. Re-run production safety checks before any production inbox approval.
9. Record a fresh Confluendo production inbox approval for the package you want
   to deliver. Do not reuse spent approval ids.
10. Run the confirmation-gated IP-17 delivery into `confluendo_inbox`.
11. Run the Vamo-owned apply function.
12. Verify the Confluendo dashboard shows `consumer_applied`.

The proposal seed is intentionally idempotent and owner-run. It does not write
to Vamo staging or production; it only restores the Confluendo control-plane
review row that makes the dashboard show LIVE data for customer-zero canary
approval.

Production inbox delivery has its own confirmation gate in
`../PRODUCTION_INBOX_RUNBOOK.md`. It writes only to Vamo production
`confluendo_inbox`; Vamo operators separately run the Vamo-owned apply function
when they are ready to mutate product tables. The current successful reference
run is package `production-inbox:vamo-place-intelligence-staging:approval:13`.
