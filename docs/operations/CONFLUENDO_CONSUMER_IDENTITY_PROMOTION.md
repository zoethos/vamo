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
can read or change the marker table. The apply and canary roles can call the narrow
reader function. If configuration is absent, it raises a named error instead of
returning a default such as `production`.

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
select * from confluendo_inbox.current_consumer_identity();
```

Expected exactly one row:

```text
staging
vamo | staging | 1
```

Verify that the restricted apply role can read only through the function:

```sql
begin;
set local role confluendo_inbox_apply;

select * from confluendo_inbox.current_consumer_identity();
-- Expected: vamo | staging | 1

select * from public.app_environment;
-- Expected: ERROR: permission denied for table app_environment

rollback;
```

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

Run the same two verification blocks. The function must return:

```text
vamo | production | 1
```

## C. Restore and worker guard

A Production-to-Staging data restore also restores this row. Before any Staging
canary preflight or wave, the Vamo Staging owner must inspect and, through an
owner-reviewed repair, restore `public.app_environment` to `staging`.

This is not the sole guard: every Confluendo worker supplies its independently
configured expected environment (`VAMO_STAGING_CANARY_ENVIRONMENT=staging` or
`VAMO_PRODUCTION_INBOX_ENVIRONMENT=production`) and fails before a write when the
target database reports a different value. The expected value must never be derived
from target-database data, including this table.

## D. Receipt-Gated Smoke

Only after both databases return their expected identity may a bounded Confluendo
Staging smoke or Production inbox delivery be attempted. The worker's independently
configured expected environment must match the database-local result, and the receipt
must report the same `consumer_key`, `target_environment`, and contract version that
the adapter returns from the connected database.

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
- Staging verification/smoke: current_app_environment() returned staging; current_consumer_identity() returned vamo | staging | 1; canary/apply roles had function-only access checked; worker expected-environment match passed
- Production project/ref:
- Production apply status:
- Production verification: current_app_environment() returned production; current_consumer_identity() returned vamo | production | 1; apply role function-only access checked; worker expected-environment match passed
- Current drift:
- If production not promoted: blocker, owner, planned date, and why drift is acceptable:
- Environment-specific objects excluded from production: no staging identity row, no canary role or canary grants
```
