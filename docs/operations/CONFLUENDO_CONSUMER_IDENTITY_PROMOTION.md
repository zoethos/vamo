# Vamo Environment Identity Promotion

Status: required before a Confluendo worker can attest or mutate a Vamo database.

Related policy: [MIGRATION_PROMOTION_POLICY.md](MIGRATION_PROMOTION_POLICY.md).

Migration:

```text
supabase/migrations/20260805210000_confluendo_inbox_consumer_identity.sql
```

## Why this is separate from the shared migration

Every Supabase project uses the database name `postgres`, so `current_database()`
cannot distinguish Vamo Staging from Vamo Production. The shared migration creates
Vamo's general `public.app_environment` marker and two narrow reader functions, but
deliberately inserts no environment. An owner then configures one row in each
database during its own promotion step.

Neither `confluendo_inbox_writer`, `confluendo_inbox_apply`, nor `vamo_canary_app`
can read or change the marker table. Each installed worker role receives only the
narrow reader function it needs: `vamo_canary_app` receives
`current_app_environment()` in Staging, while the Production apply role receives
both readers. The shared migration grants only to roles present in that database.
If configuration is absent, the reader raises a named error instead of returning a
default such as `production`.

**The marker is not a guard on its own.** It reports database-local state. A
worker is protected only when it compares that reported value with an
independently configured expected environment and fails before a write when the
two differ. No worker may derive its expectation from `app_environment` or use
`current_app_environment()` as its only environment check.

## A. Apply to Vamo Staging

Apply the migration through the normal Staging-first process. Then, in the **Vamo
Staging** SQL editor as the owner, run this once:

```sql
insert into public.app_environment (singleton, environment)
values (true, 'staging')
on conflict (singleton) do nothing;
```

Verify the configured database:

```sql
select * from public.current_app_environment();
```

Expected exactly one row:

```text
staging
```

Verify that the restricted Staging canary role can read only through the function:

```sql
begin;
set local role vamo_canary_app;

select * from public.current_app_environment();
-- Expected: staging

select * from public.app_environment;
-- Expected: ERROR: permission denied for table app_environment

rollback;
```

`confluendo_inbox_apply` is intentionally not required in Staging. The
Production-only receipt adapter is verified in the Production promotion step.

If the first `insert` affected zero rows, stop and inspect the existing row. Do not
overwrite it with an `upsert`; a correction is an owner-reviewed incident, not a
routine deployment action.

## B. Apply to Vamo Production

Only after the Staging verification is green, apply the same migration to Vamo
Production. Then, in the **Vamo Production** SQL editor as the owner, run:

```sql
insert into public.app_environment (singleton, environment)
values (true, 'production')
on conflict (singleton) do nothing;
```

As the owner, verify both readers:

```sql
select * from public.current_app_environment();
select * from confluendo_inbox.current_consumer_identity();
```

The receipt adapter must return:

```text
vamo | production | 1
```

Before the first Production inbox delivery, verify both restricted apply roles
as the owner. This is the authoritative privilege matrix; do not replace it
with a successful connection as one role.

```sql
with required_roles(role_name) as (
  values
    ('confluendo_inbox_apply'::text),
    ('confluendo_inbox_apply_app'::text)
)
select
  role_name,
  to_regrole(role_name) is not null as role_present,
  case when to_regrole(role_name) is not null
    then has_function_privilege(role_name, 'public.current_app_environment()', 'EXECUTE')
    else false end as can_read_environment,
  case when to_regrole(role_name) is not null
    then has_function_privilege(role_name, 'confluendo_inbox.current_consumer_identity()', 'EXECUTE')
    else false end as can_read_receipt,
  case when to_regrole(role_name) is not null
    then has_function_privilege(
      role_name,
      'confluendo_inbox.apply_confluendo_shipment(text,text,text)',
      'EXECUTE'
    )
    else false end as can_apply_shipment,
  case when to_regrole(role_name) is not null
    then has_table_privilege(role_name, 'public.app_environment', 'SELECT')
    else false end as can_read_marker_table,
  case when to_regrole(role_name) is not null
    then has_table_privilege(role_name, 'public.location_canonicals', 'INSERT')
    else false end as can_insert_product_rows
from required_roles
order by role_name;
```

For both roles: `role_present`, `can_read_environment`,
`can_read_receipt`, and `can_apply_shipment` must be `true`;
`can_read_marker_table` and `can_insert_product_rows` must be `false`.
Stop if any value differs.

As a direct spot check, verify the non-login apply role reads only through the
adapter:

```sql
begin;
set local role confluendo_inbox_apply;

select * from confluendo_inbox.current_consumer_identity();
-- Expected: vamo | production | 1

select * from public.app_environment;
-- Expected: ERROR: permission denied for table app_environment

rollback;
```

## C. Comparison guard and owner recovery

A Production-to-Staging data restore also restores this row. Before any Staging
canary preflight or wave, the Vamo Staging owner must inspect and, through an
owner-reviewed repair, restore `public.app_environment` to `staging`.

This is not the sole guard: every Confluendo worker supplies its independently
configured expected environment (`VAMO_STAGING_CANARY_ENVIRONMENT=staging` or
`VAMO_PRODUCTION_INBOX_ENVIRONMENT=production`) and fails before a write when the
target database reports a different value. The expected value must never be derived
from target-database data, including this table.

### Mis-seed or restore recovery

`on conflict (singleton) do nothing` deliberately refuses to overwrite a
marker. If a seed or restore leaves the wrong value, stop all affected worker
preflights and waves, record a named owner-reviewed incident, and correct it
explicitly as the database owner. This is recovery, not routine deployment.

For a **Staging** database that incorrectly reports `production`:

```sql
begin;

select singleton, environment, configured_at, configured_by
from public.app_environment
where singleton
for update;

update public.app_environment
set environment = 'staging',
    configured_at = now(),
    configured_by = current_user
where singleton
  and environment is distinct from 'staging';

select * from public.current_app_environment();
-- Expected: staging

commit;
```

For a **Production** database that incorrectly reports `staging`, use the same
owner-reviewed sequence with `environment = 'production'`, then verify both
Production reader functions and the privilege matrix in section B before any
delivery.

## D. Receipt-Gated Smoke

Only after both databases return their expected identity may a bounded Confluendo
Staging smoke or Production inbox delivery be attempted. The worker's independently
configured expected environment must match the database-local result, and the receipt
must report the same `consumer_key`, `target_environment`, and contract version that
the adapter returns from the connected database. A marker read without that independent
comparison is evidence only, not an environment safety check.

The current Confluendo receipt adapter is for the **Production inbox** and therefore
expects `target_environment = 'production'`. The Staging identity proves the same
database-local boundary and catches a copied literal, but it must never be used as a
substitute for the Production receipt or its separate approval path.

Do not use this migration to create a Vamo-side source loader, and do not seed
synthetic or live source data outside the governed Confluendo artifact path.

## Migration Promotion Checkpoint

```text
Migration promotion checkpoint:
- Migration files changed: supabase/migrations/20260805210000_confluendo_inbox_consumer_identity.sql
- Staging project/ref:
- Staging apply status:
- Staging verification/smoke: current_app_environment() returned staging; vamo_canary_app had function-only access checked; canary worker expected-environment match passed
- Production project/ref:
- Production apply status:
- Production verification: current_app_environment() returned production; current_consumer_identity() returned vamo | production | 1; both Production apply roles passed the function-only privilege matrix; worker expected-environment match passed
- Current drift:
- If production not promoted: blocker, owner, planned date, and why drift is acceptable:
- Environment-specific objects excluded from production: no staging identity row or canary role/grant; no Production apply-role grant is expected in Staging
```
