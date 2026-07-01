# IP-17 - Vamo Production Inbox Delivery Runbook

Status: implementation runbook for a confirmation-gated production inbox
delivery. This runbook does not authorize a live production run by itself.

Confluendo is the ingestion platform. Vamo is the consumer. For production,
Confluendo delivers a reviewed shipment package into Vamo's
`confluendo_inbox` schema only. Vamo owns the later apply step into
`public.location_canonicals` and `public.location_source_refs`.

## Safety Model

IP-17 is a delivery-to-inbox slice, not a direct production-write slice.

Confluendo may:

- create a package from a reviewed dry run,
- require staging-canary evidence,
- require `ingestion_admin` + MFA/AAL2 + fresh step-up + audit reason,
- write the package into `confluendo_inbox.shipments` and
  `confluendo_inbox.shipment_items`,
- record Confluendo control-plane approval and delivery ledger rows.

Confluendo must not:

- write directly to Vamo production product tables,
- create or modify Vamo product RLS policies,
- execute Vamo's final apply function automatically,
- run with the staging canary role on production,
- run if a staging guard/sentinel exists on the target,
- calculate package or payload checksums in JavaScript.

Checksums are computed inside Vamo Postgres with:

```sql
extensions.digest(convert_to(payload::jsonb::text, 'UTF8'), 'sha256')
```

This is deliberate: the inbox writer and Vamo's apply function must agree on
Postgres' canonical `jsonb::text` representation.

## Prerequisites

### 1. Vamo production schema

Apply these migrations to Vamo production, in order:

1. `supabase/migrations/20260625155733_place_intelligence_cache.sql`
2. `supabase/migrations/20260701100233_confluendo_inbox.sql`
3. `supabase/migrations/20260701121500_confluendo_inbox_writer_digest_usage.sql`

The final migration grants the inbox writer usage on the `extensions` schema so
it can call `extensions.digest(...)` while still having no privileges on Vamo
product tables.

### 2. Production inbox login role

The migration creates the permission role `confluendo_inbox_writer` as
`NOLOGIN`. The Vamo DBA must provision a separate login role for the production
DSN and grant it this permission role.

Example, run by the Vamo production DBA:

```sql
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'confluendo_inbox_app') then
    create role confluendo_inbox_app
      login
      password '<generated-password>'
      nosuperuser
      nocreatedb
      nocreaterole
      noinherit
      nobypassrls;
  else
    alter role confluendo_inbox_app
      login
      password '<generated-password>'
      nosuperuser
      nocreatedb
      nocreaterole
      noinherit
      nobypassrls;
  end if;
end;
$$;

grant confluendo_inbox_writer to confluendo_inbox_app;
```

Use the resulting login role in `VAMO_PRODUCTION_INBOX_DATABASE_URL`. Do not use
the Supabase owner/admin role for the Confluendo production inbox run.

### 3. Production safety checks

Before a live run, verify:

```sql
select exists (
  select 1 from pg_roles where rolname = 'vamo_canary_app'
) as staging_canary_role_present;

select to_regclass('confluendo_guard.environment_sentinel') as staging_sentinel_table;

select
  has_schema_privilege('confluendo_inbox_app', 'confluendo_inbox', 'USAGE') as can_use_inbox,
  has_table_privilege('confluendo_inbox_app', 'confluendo_inbox.shipments', 'SELECT, INSERT') as can_insert_shipments,
  has_column_privilege('confluendo_inbox_app', 'confluendo_inbox.shipments', 'status', 'UPDATE') as can_update_shipment_status,
  has_table_privilege('confluendo_inbox_app', 'confluendo_inbox.shipment_items', 'SELECT, INSERT') as can_insert_items,
  has_table_privilege('confluendo_inbox_app', 'public.location_canonicals', 'INSERT, UPDATE, DELETE') as can_write_canonicals,
  has_table_privilege('confluendo_inbox_app', 'public.location_source_refs', 'INSERT, UPDATE, DELETE') as can_write_refs;
```

Expected:

- `staging_canary_role_present = false`
- `staging_sentinel_table = null`
- first four privilege checks are `true`
- final two product-table write checks are `false`

### 4. Confluendo control-plane state

The Confluendo dashboard must show:

- live proposal row, not sample fallback,
- reviewed dry run compatible,
- `wroteToTarget=false`,
- staging canary evidence present,
- no prior active production inbox delivery for the same target/proposal.

## Approval

Use `/admin/ingestion` to record the production inbox approval.

Required:

- `ingestion_admin` principal,
- project scope `vamo`,
- AAL2 session,
- fresh MFA step-up,
- non-empty audit reason,
- explicit transition:
  `approved_for_production_inbox -> production_inbox_delivered`.

The dashboard approval records the decision in the Confluendo control DB only.
It does not connect to Vamo production and it does not write the inbox package.

## Dry Preview

From `Z:\vamo-web-dashboard\web`:

```powershell
npm --workspace @confluendo/ingestion-platform run ip17:production-inbox
```

Expected without live gates:

- prints the package preview,
- reports missing gates,
- prints `NO WRITE PERFORMED`,
- exits non-zero.

This is a successful safety preview, not a failed delivery.

## Confirmation-Gated Live Delivery

Only after production safety checks and dashboard approval are complete:

```powershell
$env:CONFIRM_VAMO_PRODUCTION_INBOX = "YES"
$env:VAMO_PRODUCTION_INBOX_ENVIRONMENT = "production"
$env:VAMO_PRODUCTION_INBOX_APPROVAL_ID = "<approval-audit-id>"
$env:VAMO_PRODUCTION_INBOX_DATABASE_URL = "<production-inbox-login-dsn>"
$env:INGESTION_CONTROL_DATABASE_URL = "<confluendo-control-dsn>"

npm --workspace @confluendo/ingestion-platform run ip17:production-inbox -- --execute
```

The live command:

1. loads the recorded approval from the Confluendo control DB,
2. rejects expired or replayed approvals,
3. rebuilds the package from the reviewed run,
4. proves the target is production and not staging,
5. computes payload and package checksums inside Vamo Postgres,
6. inserts only into `confluendo_inbox`,
7. records the Confluendo delivery ledger.

## Vamo Apply Step

After delivery, the package is still not applied to Vamo product tables. Vamo
production operators decide when to run:

```sql
select confluendo_inbox.apply_confluendo_shipment(
  '<package_id>',
  '<vamo-approved-by>',
  '<vamo-approval-reason>'
);
```

The apply function validates:

- package exists,
- package target is production,
- schema contract is supported,
- payload checksums match Postgres-computed values,
- package checksum matches item checksums,
- delete operations are absent,
- item payloads satisfy Vamo product-shape rules.

## Rollback And Reconciliation

IP-17 does not automate production rollback. Vamo owns the product-table apply
and any reversal. Confluendo owns only the package delivery ledger.

If inbox delivery succeeds but the Confluendo ledger write fails:

1. do not rerun blindly,
2. inspect `confluendo_inbox.shipments` and `shipment_items` by `package_id`,
3. reconcile the Confluendo control ledger manually or with a future repair
   command,
4. only rerun if the package checksum matches and the command reports
   idempotent success.

If Vamo apply fails, inspect `confluendo_inbox.apply_log` and keep the package
in the inbox for diagnosis. Do not ask Confluendo to mutate product tables.

## Stop Conditions

Stop before live delivery if any of these are true:

- production safety checks are incomplete,
- production DSN uses an owner/admin role instead of the inbox login role,
- `vamo_canary_app` exists on the target,
- `confluendo_guard.environment_sentinel` exists on the target,
- product-table write privileges are granted to the inbox login role,
- dashboard source is sample fallback,
- staging canary evidence is missing,
- MFA step-up is stale,
- approval id is missing, expired, or already used,
- package checksum or item checksum cannot be computed by Vamo Postgres.
