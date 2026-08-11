# Function Privilege Convergence Promotion

Migration: `supabase/migrations/20260811140000_function_privilege_convergence.sql`

Purpose: converge `public` function execution privileges in Staging and
Production. The migration removes the historical default grants that exposed
functions to `anon` and `authenticated`, then restores only the declared RPC
allowlists.

This is a manual SQL-Editor promotion. Do not use `supabase db push` or any
linked CLI migration command until the migration ledger is reconciled.

## Preconditions

1. `20260805210000_confluendo_inbox_consumer_identity.sql` is already applied.
2. `public.app_environment` is seeded with the correct value in the target:
   `staging` for Staging and `production` for Production.
3. The current public-function privilege matrix has been captured for the
   checkpoint. The migration changes permissions; it does not alter product
   rows.

The environment marker is required. `public.current_app_environment()` fails
closed when it is absent, so this migration should fail rather than guess which
database it is changing.

## Staging Apply

1. In the Vamo Staging SQL Editor, open and run exactly:
   `supabase/migrations/20260811140000_function_privilege_convergence.sql`.
2. Run the verification block below.
3. Run `tool/rls_smoke.dart` against Staging with its normal service-role
   configuration. The two lifecycle smoke fixtures must remain available only
   there.

```sql
select
  p.oid::regprocedure::text as function_signature,
  has_function_privilege('anon', p.oid, 'execute') as anon_can_execute,
  has_function_privilege('authenticated', p.oid, 'execute') as authenticated_can_execute,
  has_function_privilege('service_role', p.oid, 'execute') as service_role_can_execute
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.prokind = 'f'
  and (
    has_function_privilege('anon', p.oid, 'execute')
    or has_function_privilege('authenticated', p.oid, 'execute')
  )
order by function_signature;

select
  to_regprocedure('public.rls_smoke_set_close_requested_at(uuid,timestamp with time zone)') is not null
    as has_close_requested_fixture,
  to_regprocedure('public.rls_smoke_set_close_notified_at(uuid,uuid,timestamp with time zone)') is not null
    as has_close_notified_fixture,
  has_function_privilege('service_role', 'public.run_trip_lifecycle_jobs()', 'execute')
    as service_can_run_lifecycle,
  has_function_privilege('authenticated', 'public.run_trip_lifecycle_jobs()', 'execute')
    as authenticated_can_run_lifecycle,
  has_function_privilege('anon', 'public.run_trip_lifecycle_jobs()', 'execute')
    as anon_can_run_lifecycle;
```

Expected Staging result:

- `get_trip_preview(text)` is the only `anon` executable function.
- The declared app RPCs are executable by `authenticated`; service-only
  functions are not.
- Both fixture-presence fields are `true`.
- `service_can_run_lifecycle` is `true`; the two final fields are `false`.

## Production Apply

1. Do not run the Staging RLS smoke in Production.
2. In the Vamo Production SQL Editor, run exactly:
   `supabase/migrations/20260811140000_function_privilege_convergence.sql`.
3. Run the same matrix query above.
4. Run this Production-only fixture check:

```sql
select
  to_regprocedure('public.rls_smoke_set_close_requested_at(uuid,timestamp with time zone)') is null
    as close_requested_fixture_absent,
  to_regprocedure('public.rls_smoke_set_close_notified_at(uuid,uuid,timestamp with time zone)') is null
    as close_notified_fixture_absent,
  has_function_privilege('authenticated', 'public.identity_integrity_summary()', 'execute')
    as authenticated_can_read_identity_summary,
  has_function_privilege('anon', 'public.identity_integrity_summary()', 'execute')
    as anon_can_read_identity_summary;
```

Expected Production result: both fixture-absence fields are `true`; both
identity-summary access fields are `false`.

After the schema check, deploy the already-reviewed lifecycle worker only if
the production environment configuration is unchanged. Do not manually invoke
it: wait for the established 06:00 UTC schedule and inspect its heartbeat.
Do not create or rotate Production `CRON_SECRET`.

## Promotion Checkpoint

```text
Migration promotion checkpoint:
- Migration files changed: 20260811140000_function_privilege_convergence.sql
- Staging project/ref:
- Staging apply status:
- Staging verification/smoke:
- Production project/ref:
- Production apply status:
- Production verification:
- Current drift:
- If production not promoted: blocker, owner, planned date, and why drift is acceptable:
- Environment-specific objects excluded from production: rls_smoke_set_close_requested_at, rls_smoke_set_close_notified_at
```
