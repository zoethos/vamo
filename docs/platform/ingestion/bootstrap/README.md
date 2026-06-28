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

## Guardrails

- Never run a Vamo staging canary before phases 1-7 are green.
- Never set `CONFIRM_VAMO_STAGING_CANARY=YES` during bootstrap.
- Never run `--execute` during bootstrap verification.
- Never grant Confluendo write access to Vamo production.
- Never create a production sentinel row with `value='staging'`.
- Keep Confluendo control DB credentials separate from Vamo target DB
  credentials.
- Keep customer-specific seed artifacts in this bootstrap folder or a future
  consumer-package folder, not in generic platform runtime code.

## Disaster Recovery Shape

For a fresh Confluendo instance serving Vamo:

1. Restore/apply the Confluendo control schema.
2. Bootstrap the Confluendo runtime role and the `vamo` project row.
3. Run the Vamo proposal seed in `sql/ip16_vamo_live_proposal_seed.sql`.
4. Apply Vamo's place-intelligence cache migration to Vamo staging and
   production as appropriate.
5. Provision the Vamo staging sentinel table and `vamo_canary_app` role.
6. Re-run read-only readiness checks before any approval or write.

The proposal seed is intentionally idempotent and owner-run. It does not write
to Vamo staging or production; it only restores the Confluendo control-plane
review row that makes the dashboard show LIVE data for customer-zero canary
approval.
