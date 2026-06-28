# Place-Intelligence Cache Promotion Checklist

Status: operator checklist for promoting the Vamo place-intelligence cache
migration from staging to production.

Related policy: `docs/operations/MIGRATION_PROMOTION_POLICY.md`.

Migration:

```text
supabase/migrations/20260625155733_place_intelligence_cache.sql
```

This migration creates the Vamo app-owned place cache schema used by the
Confluendo customer-zero ingestion path. It is a Vamo app schema migration, so
it must be promoted from staging to production under the normal migration
promotion policy. Confluendo canary-only objects remain staging-only and must
not be promoted to production.

## What The Migration Creates

Apply the migration as a whole. Do not cherry-pick only the two shipment tables:
the file creates a dependency graph with provider policies, aliases, caches,
observations, indexes, RLS posture, and helper functions.

Key tables for the first Confluendo canary:

- `public.location_canonicals`
- `public.location_source_refs`

Important properties:

- `location_source_refs` depends on `location_canonicals`.
- `location_canonicals` depends on `location_provider_policies`.
- RLS is enabled on the global cache tables.
- `anon` and `authenticated` are revoked from the cache tables.
- `service_role` is granted privileges by the migration.
- The migration includes a PII-firewall guard for global location tables.

## Safety Split

Promote to both staging and production:

- Vamo app place-intelligence cache schema.
- RLS posture and app-owned helper functions in the migration.
- Seed provider policy rows included in the migration.

Staging only, never production:

- `confluendo_guard.environment_sentinel`.
- `vamo_canary_app`.
- Confluendo canary grants.
- Role-scoped canary RLS policies.
- Any staging proof with `value='staging'`.

## A. Apply To Vamo Staging

Preferred when this exact migration is the only intended database change:

```bash
psql "$VAMO_STAGING_DATABASE_URL" \
  -f supabase/migrations/20260625155733_place_intelligence_cache.sql
```

Alternative migration-runner path, only after confirming all pending migrations
are intended for staging:

```bash
supabase link --project-ref <VAMO_STAGING_PROJECT_REF>
supabase db push
```

Do not use production credentials in this step.

## B. Verify Vamo Staging

Run as a read-only structural check:

```sql
select
  to_regclass('public.location_canonicals') as canonicals,
  to_regclass('public.location_source_refs') as source_refs;
```

Expected: both columns are non-null.

Verify RLS:

```sql
select relname, relrowsecurity
from pg_class
where relnamespace = 'public'::regnamespace
  and relname in ('location_canonicals', 'location_source_refs')
order by relname;
```

Expected: both rows have `relrowsecurity = true`.

Optional policy/grant visibility:

```sql
select table_name, grantee, privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
  and table_name in ('location_canonicals', 'location_source_refs')
order by table_name, grantee, privilege_type;
```

## C. Apply The Same Migration To Vamo Production

Run only after staging verification passes.

Preferred exact-file path:

```bash
psql "$VAMO_PRODUCTION_DATABASE_URL" \
  -f supabase/migrations/20260625155733_place_intelligence_cache.sql
```

Alternative migration-runner path, only after confirming all pending migrations
are intended for production:

```bash
supabase link --project-ref <VAMO_PRODUCTION_PROJECT_REF>
supabase db push
```

Do not run Confluendo canary setup on production.

## D. Verify Vamo Production

Run the same structural checks as staging:

```sql
select
  to_regclass('public.location_canonicals') as canonicals,
  to_regclass('public.location_source_refs') as source_refs;

select relname, relrowsecurity
from pg_class
where relnamespace = 'public'::regnamespace
  and relname in ('location_canonicals', 'location_source_refs')
order by relname;
```

Expected:

- both tables exist,
- RLS is enabled on both.

## E. Confirm Production Did Not Receive Canary Artifacts

Production must not have Confluendo staging proof or write role artifacts.

```sql
select to_regclass('confluendo_guard.environment_sentinel') as sentinel_table;

select count(*) as confluendo_guard_schema
from pg_namespace
where nspname = 'confluendo_guard';

select rolname
from pg_roles
where rolname = 'vamo_canary_app';

select grantee, table_name, privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
  and table_name in ('location_canonicals', 'location_source_refs')
  and grantee = 'vamo_canary_app';
```

Expected on production:

- `sentinel_table = null`
- `confluendo_guard_schema = 0`
- no `vamo_canary_app` role
- zero canary grants

## Migration Promotion Checkpoint

Use this exact checkpoint in the handoff:

```text
Migration promotion checkpoint:
- Migration files changed: supabase/migrations/20260625155733_place_intelligence_cache.sql
- Staging project/ref:
- Staging apply status:
- Staging verification/smoke:
- Production project/ref:
- Production apply status:
- Production verification:
- Current drift:
- If production not promoted: blocker, owner, planned date, and why drift is acceptable:
- Environment-specific objects excluded from production: confluendo_guard.environment_sentinel, vamo_canary_app, canary grants/RLS policies
```

Allowed production statuses are defined in
`docs/operations/MIGRATION_PROMOTION_POLICY.md`.

## Notes

- This checklist does not execute the Confluendo staging canary.
- Do not set `CONFIRM_VAMO_STAGING_CANARY=YES`.
- Do not run the Confluendo `--execute` path.
- Do not create `vamo_canary_app` or the sentinel on production.
- Once staging and production are schema-aligned, Confluendo canary enablement
  continues as a separate staging-only operation.
