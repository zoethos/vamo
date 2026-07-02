# Vamo Customer-Zero Bootstrap

This document provisions the Vamo consumer instance that Confluendo operates
against for IP-16 and IP-17. It is deliberately customer-specific: Vamo
supplies the target schema, target database, inbox schema, and product apply
function; Confluendo supplies the control-plane, approval policy, shipment
package, and delivery adapter.

Use this after the Confluendo control DB phases in `README.md` have completed.

## Phase 4 - Vamo Target Cache Schema

Run this on **Vamo staging first**. Apply the Vamo migration that creates the
place-intelligence cache tables:

```text
Z:\vamo\supabase\migrations\20260625155733_place_intelligence_cache.sql
```

Preferred manual path when only this migration should be applied:

1. Open the Vamo staging Supabase project.
2. Confirm the project ref/host is staging, not production.
3. Paste and run the full migration SQL as the database owner.

Verify:

```sql
select
  to_regclass('public.location_canonicals') as location_canonicals,
  to_regclass('public.location_source_refs') as location_source_refs;
```

Expected:

```text
public.location_canonicals
public.location_source_refs
```

Verify RLS:

```sql
select relname, relrowsecurity
from pg_class
where relnamespace = 'public'::regnamespace
  and relname in ('location_canonicals', 'location_source_refs');
```

Expected: both rows have `relrowsecurity = true`.

### Production Schema

Production may receive the same place-intelligence cache migration when the
Vamo app release needs it. Production bootstrap is schema-only:

- apply the place cache migration,
- verify the tables and RLS,
- keep `anon` and `authenticated` revoked as the migration defines,
- do not create `vamo_canary_app`,
- do not create a sentinel row with `value='staging'`,
- do not grant Confluendo target writes.

## Phase 5 - Vamo Staging Sentinel And Canary Role

Run this only after the two target tables exist on **Vamo staging**.

The staging proof is a DBA-provisioned row. Do not use
`ALTER DATABASE ... SET` custom parameters: Supabase rejects that pattern, and
the adapter now reads the sentinel table instead.

### Sentinel Table

```sql
begin;

create schema if not exists confluendo_guard;

create table if not exists confluendo_guard.environment_sentinel (
  key text primary key,
  value text not null,
  created_at timestamptz not null default now()
);

insert into confluendo_guard.environment_sentinel (key, value)
values ('environment', 'staging')
on conflict (key) do update set value = excluded.value;

revoke all on schema confluendo_guard from public, anon, authenticated;
revoke all on all tables in schema confluendo_guard from public, anon, authenticated;

commit;
```

Verify:

```sql
select value as env
from confluendo_guard.environment_sentinel
where key = 'environment';
```

Expected: `staging`.

### Canary Role

Choose the role name:

```text
vamo_canary_app
```

Create or update it on Vamo staging. Replace only the password.

```sql
begin;

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'vamo_canary_app') then
    create role vamo_canary_app
      login
      password 'REPLACE_WITH_A_STRONG_UNIQUE_PASSWORD'
      nosuperuser
      nocreatedb
      nocreaterole
      noinherit
      nobypassrls
      noreplication;
  else
    alter role vamo_canary_app
      login
      password 'REPLACE_WITH_A_STRONG_UNIQUE_PASSWORD'
      nosuperuser
      nocreatedb
      nocreaterole
      noinherit
      nobypassrls
      noreplication;
  end if;
end $$;

grant connect on database postgres to vamo_canary_app;

grant usage on schema confluendo_guard to vamo_canary_app;
grant select on confluendo_guard.environment_sentinel to vamo_canary_app;

grant usage on schema public to vamo_canary_app;
grant select, insert, update on public.location_canonicals to vamo_canary_app;
grant select, insert, update on public.location_source_refs to vamo_canary_app;

commit;
```

No `DELETE`, no `TRUNCATE`, no table ownership, no `BYPASSRLS`.

### RLS Policies

The Vamo migration enables RLS on the cache tables. Add role-scoped policies
for the canary role only.

```sql
begin;

drop policy if exists vamo_canary_select on public.location_canonicals;
drop policy if exists vamo_canary_insert on public.location_canonicals;
drop policy if exists vamo_canary_update on public.location_canonicals;

create policy vamo_canary_select on public.location_canonicals
  for select to vamo_canary_app using (true);
create policy vamo_canary_insert on public.location_canonicals
  for insert to vamo_canary_app with check (true);
create policy vamo_canary_update on public.location_canonicals
  for update to vamo_canary_app using (true) with check (true);

drop policy if exists vamo_canary_select on public.location_source_refs;
drop policy if exists vamo_canary_insert on public.location_source_refs;
drop policy if exists vamo_canary_update on public.location_source_refs;

create policy vamo_canary_select on public.location_source_refs
  for select to vamo_canary_app using (true);
create policy vamo_canary_insert on public.location_source_refs
  for insert to vamo_canary_app with check (true);
create policy vamo_canary_update on public.location_source_refs
  for update to vamo_canary_app using (true) with check (true);

commit;
```

Policy names are reused on two different tables, which is valid in Postgres.
No delete policy is created.

### Verification

```sql
select value as env
from confluendo_guard.environment_sentinel
where key = 'environment';

select
  has_table_privilege('vamo_canary_app', 'confluendo_guard.environment_sentinel', 'SELECT') as can_read_sentinel,
  has_table_privilege('vamo_canary_app', 'public.location_canonicals', 'SELECT, INSERT, UPDATE') as can_upsert_canonicals,
  has_table_privilege('vamo_canary_app', 'public.location_source_refs', 'SELECT, INSERT, UPDATE') as can_upsert_source_refs,
  has_table_privilege('vamo_canary_app', 'public.location_canonicals', 'DELETE') as can_delete_canonicals,
  has_table_privilege('vamo_canary_app', 'public.location_source_refs', 'DELETE') as can_delete_source_refs;

select rolname, rolsuper, rolbypassrls
from pg_roles
where rolname = 'vamo_canary_app';

select tablename, policyname, cmd
from pg_policies
where schemaname = 'public'
  and tablename in ('location_canonicals', 'location_source_refs')
order by tablename, cmd, policyname;
```

Expected:

- `env = staging`
- can read sentinel = `true`
- can upsert the two target tables = `true`
- delete privileges = `false`
- `rolsuper = false`
- `rolbypassrls = false`
- policies exist only for SELECT, INSERT, UPDATE on the two target tables

## Rollback Posture

The canary role intentionally has no delete permission. That means an automated
rollback of newly inserted rows cannot run under `vamo_canary_app`; rollback of
updates can still restore prior values. If inserted-row rollback is needed, run
it as a separate, explicitly approved owner/operator action using the shipment
ledger from Confluendo control DB.

Do not add `DELETE` to `vamo_canary_app` just to make rollback convenient. The
first canary's write role is intentionally narrower than the rollback role.

## Phase 6 - Vamo Production Inbox Schema

Run this on **Vamo production only after the place-intelligence cache migration
has already been promoted to production** under
`docs/operations/MIGRATION_PROMOTION_POLICY.md`.

Apply these migrations in order:

```text
Z:\vamo\supabase\migrations\20260701100233_confluendo_inbox.sql
Z:\vamo\supabase\migrations\20260701121500_confluendo_inbox_writer_digest_usage.sql
```

They create:

- `confluendo_inbox.shipments`
- `confluendo_inbox.shipment_items`
- `confluendo_inbox.apply_log`
- `confluendo_inbox.apply_confluendo_shipment(...)`
- the `NOLOGIN` permission role `confluendo_inbox_writer`
- the `extensions` schema usage grant needed for Postgres-side checksums

Verify:

```sql
select table_schema, table_name
from information_schema.tables
where table_schema = 'confluendo_inbox'
order by table_name;

select has_schema_privilege('confluendo_inbox_writer', 'extensions', 'USAGE') as can_digest;
```

Expected tables: `apply_log`, `shipment_items`, `shipments`.
Expected `can_digest = true`.

## Phase 7 - Vamo Production Inbox Login Role

`confluendo_inbox_writer` is intentionally `NOLOGIN`. Provision the actual
least-privilege login role separately and grant it membership in the writer
role.

```sql
begin;

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'confluendo_inbox_app') then
    create role confluendo_inbox_app
      login
      password 'REPLACE_WITH_A_STRONG_UNIQUE_PASSWORD'
      nosuperuser
      nocreatedb
      nocreaterole
      noinherit
      nobypassrls
      noreplication;
  else
    alter role confluendo_inbox_app
      login
      password 'REPLACE_WITH_A_STRONG_UNIQUE_PASSWORD'
      nosuperuser
      nocreatedb
      nocreaterole
      noinherit
      nobypassrls
      noreplication;
  end if;
end $$;

grant confluendo_inbox_writer to confluendo_inbox_app;

commit;
```

Use this role, not the Supabase owner role, for
`VAMO_PRODUCTION_INBOX_DATABASE_URL`.

Verify:

```sql
select rolname, rolcanlogin, rolsuper, rolbypassrls
from pg_roles
where rolname in ('confluendo_inbox_writer', 'confluendo_inbox_app')
order by rolname;

select
  pg_has_role('confluendo_inbox_app', 'confluendo_inbox_writer', 'member') as inherits_writer,
  has_schema_privilege('confluendo_inbox_app', 'confluendo_inbox', 'USAGE') as can_use_inbox,
  has_table_privilege('confluendo_inbox_app', 'confluendo_inbox.shipments', 'SELECT, INSERT') as can_insert_shipments,
  has_column_privilege('confluendo_inbox_app', 'confluendo_inbox.shipments', 'status', 'UPDATE') as can_update_status,
  has_table_privilege('confluendo_inbox_app', 'confluendo_inbox.shipment_items', 'SELECT, INSERT') as can_insert_items,
  has_table_privilege('confluendo_inbox_app', 'public.location_canonicals', 'INSERT, UPDATE, DELETE') as can_write_canonicals,
  has_table_privilege('confluendo_inbox_app', 'public.location_source_refs', 'INSERT, UPDATE, DELETE') as can_write_refs;
```

Expected:

- `confluendo_inbox_writer`: `rolcanlogin = false`
- `confluendo_inbox_app`: `rolcanlogin = true`
- both roles: `rolsuper = false`, `rolbypassrls = false`
- `inherits_writer = true`
- inbox/schema privilege checks = `true`
- product-table write checks = `false`

## Phase 8 - Production Delivery And Vamo Apply Proof

Confluendo delivery writes only to Vamo production `confluendo_inbox`.
Vamo applies separately:

```sql
select confluendo_inbox.apply_confluendo_shipment(
  '<package_id>',
  '<vamo-approved-by>',
  '<vamo-approval-reason>'
);
```

Current customer-zero evidence:

- Package `production-inbox:vamo-place-intelligence-staging:approval:10`
  failed apply because it was produced before IP-17.1 added `canonical_key` to
  source-ref payloads. It is a historical audit artifact; do not retry it.
- Package `production-inbox:vamo-place-intelligence-staging:approval:13`
  applied successfully: `applied=2`, `skipped=0`, `rejected=0`.
- `/admin/ingestion` shows the package as applied after the Vamo apply step.

For the next package, start from a new Confluendo proposal/run and record a new
production inbox approval. Do not reuse spent approval ids or package ids.
