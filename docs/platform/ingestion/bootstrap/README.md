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

After IP-18.6.1, phases 1–2 must include the production package-wave tables
(`ingestion_batch_production_package_waves`,
`ingestion_batch_production_package_wave_items`) before the dashboard or CLI
can load live package-wave state. Missing tables degrade gracefully to no
package-wave projection.

After IP-18.8.7, phases 1–2 must also include
`ingestion_platform.set_autonomy_production_handoff(...)`. The admin console
uses that audited function to enable or disable autonomous production package
approval/delivery. The runtime role must receive `EXECUTE` on the function, but
still must not receive direct `UPDATE` on `ingestion_autonomy_policies`.
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

Before running either `control_schema.sql` or
`control_bootstrap_confluendo.sql`, positively confirm that the SQL editor is
connected to the **Confluendo control DB**. Do not rely on the presence of the
`confluendo_app` role as proof: Postgres roles are cluster-level, so that role
can exist even when the selected database/schema is wrong.

For the current Vamo customer-zero control plane, the Supabase project is
`confluendo-control` (`agrcvzlkorlzwoxtkcft`). In the SQL editor, confirm the
project selector/ref first, then run this read-only preflight:

```sql
select
  current_database() as database_name,
  current_user as executing_role,
  to_regclass('ingestion_platform.ingestion_projects') is not null as has_control_projects_table;
```

For an existing live control DB, expected values are `database_name = postgres`
and `has_control_projects_table = true`. Then confirm the current customer-zero
project row:

```sql
select exists (
  select 1
  from ingestion_platform.ingestion_projects
  where project_key = 'vamo'
) as has_vamo_control_project;
```

Expected: `true`. For a fresh disaster-recovery restore, the table/project row
may not exist yet, but the operator must still confirm the Supabase project/ref
out of band before applying schema.

After applying `control_schema.sql`, run
`../../../../web/packages/ingestion-platform/core/sql/control_bootstrap_confluendo.sql`
as the Confluendo control DB owner. That bootstrap must grant the runtime role
(`confluendo_app`) both read access for the dashboard and the narrow Confluendo
control-plane writes used by IP-16 through IP-18.4:

```sql
grant usage on schema ingestion_platform to confluendo_app;
grant select on all tables in schema ingestion_platform to confluendo_app;

grant insert, update on ingestion_platform.ingestion_targets to confluendo_app;
grant insert, update on ingestion_platform.ingestion_shipments to confluendo_app;
grant insert, delete on ingestion_platform.ingestion_shipment_items to confluendo_app;

grant update (
  status,
  blockers,
  run_report,
  updated_at
) on ingestion_platform.ingestion_batch_queue_items to confluendo_app;
grant insert, update on ingestion_platform.ingestion_batch_dry_run_executions to confluendo_app;
grant insert, update on ingestion_platform.ingestion_batch_canary_waves to confluendo_app;
grant insert, update on ingestion_platform.ingestion_batch_canary_wave_items to confluendo_app;
grant insert, update on ingestion_platform.ingestion_autonomy_runs to confluendo_app;
grant execute on function ingestion_platform.promote_autonomy_ramp(
  text, text, text, text, text, text, text
) to confluendo_app;
grant execute on function ingestion_platform.set_autonomy_production_handoff(
  text, text, boolean, boolean, text, text, text
) to confluendo_app;

grant insert on ingestion_platform.ingestion_audit_log to confluendo_app;
grant usage, select on all sequences in schema ingestion_platform to confluendo_app;
```

IP-18.7 autonomy foundation: `ingestion_autonomy_policies` is **SELECT** only via
the blanket `grant select on all tables` (policy authoring remains owner-run).
`ingestion_autonomy_runs` receives `INSERT`/`UPDATE` for future agent cycles.
Neither table receives `DELETE` grants. IP-18.7.4 adds the app-callable
`promote_autonomy_ramp(...)` function for audited ramp changes, but still no
direct `UPDATE` grant on `ingestion_autonomy_policies`. IP-18.8.7 adds the
app-callable `set_autonomy_production_handoff(...)` function for audited
production package handoff changes; it follows the same function-only grant
pattern and keeps Apply to Vamo disabled for autonomy.

These are Confluendo **control-plane** grants only. They do not grant
Confluendo any write access to Vamo production, and they do not replace the
separate Vamo staging `vamo_canary_app` role used for the bounded target write.

Verify the shipment-ledger grants before running a live canary:

```sql
select
  current_database() as database_name,
  current_user as executing_role,
  to_regclass('ingestion_platform.ingestion_batch_dry_run_executions') is not null as has_execution_table,
  has_table_privilege('confluendo_app', 'ingestion_platform.ingestion_targets', 'SELECT, INSERT, UPDATE') as can_upsert_targets,
  has_table_privilege('confluendo_app', 'ingestion_platform.ingestion_shipments', 'SELECT, INSERT, UPDATE') as can_upsert_shipments,
  has_table_privilege('confluendo_app', 'ingestion_platform.ingestion_shipment_items', 'SELECT, INSERT, DELETE') as can_replace_shipment_items,
  has_column_privilege('confluendo_app', 'ingestion_platform.ingestion_batch_queue_items', 'status', 'UPDATE') as can_update_queue_status,
  has_column_privilege('confluendo_app', 'ingestion_platform.ingestion_batch_queue_items', 'run_report', 'UPDATE') as can_update_queue_report,
  has_column_privilege('confluendo_app', 'ingestion_platform.ingestion_batch_queue_items', 'blockers', 'UPDATE') as can_update_queue_blockers,
  has_table_privilege('confluendo_app', 'ingestion_platform.ingestion_batch_dry_run_executions', 'SELECT, INSERT, UPDATE') as can_write_dry_run_executions,
  has_table_privilege('confluendo_app', 'ingestion_platform.ingestion_audit_log', 'SELECT, INSERT') as can_record_audit,
  case
    when to_regclass('ingestion_platform.ingestion_batch_dry_run_executions_id_seq') is null then false
    else has_sequence_privilege('confluendo_app', 'ingestion_platform.ingestion_batch_dry_run_executions_id_seq', 'USAGE')
  end as can_use_dry_run_execution_sequence,
  case
    when to_regclass('ingestion_platform.ingestion_audit_log_id_seq') is null then false
    else has_sequence_privilege('confluendo_app', 'ingestion_platform.ingestion_audit_log_id_seq', 'USAGE')
  end as can_use_audit_sequence;
```

Expected: `database_name = postgres` and all boolean values are `true`.

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
| `production-inbox:vamo-place-intelligence-staging:approval:10` | `consumer_apply_failed` | Historical failed package (legacy target-key naming; immutable audit history). It was delivered before IP-17.1 added `canonical_key` to source-ref payloads. Do not retry it. |
| `production-inbox:vamo-place-intelligence-staging:approval:13` | `consumer_applied` | Historical successful proof (legacy target-key naming; immutable audit history). Vamo applied 2 rows, skipped 0, rejected 0. `/admin/ingestion` shows the package as applied. New proposals use `vamo-place-intelligence`. |

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
