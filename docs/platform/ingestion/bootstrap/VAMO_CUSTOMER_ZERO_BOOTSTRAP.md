# Vamo Customer-Zero Bootstrap

This document provisions the Vamo consumer instance that Confluendo operates
against for IP-16. It is deliberately customer-specific: Vamo supplies the
target schema and target database; Confluendo supplies the control-plane,
approval policy, and shipment adapter.

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
