# Disposable Database Smoke Safety

The ingestion-platform DB smokes reset schemas, roles, and target tables. They
must never point to Confluendo Control Staging, Confluendo Control Production,
or a Vamo target database.

`INGESTION_TEST_DATABASE_URL` is guarded in the test runner and in every
destructive smoke-suite entry point:

- A local database is accepted only on `localhost`, `127.0.0.1`, or `::1` on
  port `55433`.
- Any other host requires both `CONFIRM_DISPOSABLE_TEST_DB=YES` and an exact
  host entry in `INGESTION_TEST_DATABASE_HOST_ALLOWLIST`.
- A test URL matching or sharing a host with a configured Confluendo Control or
  Vamo database URL is always refused.
- Raw `DROP`, `TRUNCATE`, and `DELETE FROM` setup SQL is prohibited in every
  package smoke-test directory outside `core/test/disposable-test-database.ts`.
- The package test command removes compiled test output before discovery, so a
  branch switch cannot run stale smoke files from `dist`.

Use a dedicated, disposable database only. Do not source
`INGESTION_TEST_DATABASE_URL` from `.env.staging.local` or
`.env.production.local`.

## Examples

Local disposable Postgres:

```powershell
$env:INGESTION_TEST_DATABASE_URL = "postgresql://postgres:postgres@127.0.0.1:55433/ingestion_test"
npm --workspace @confluendo/ingestion-platform test
Remove-Item Env:\INGESTION_TEST_DATABASE_URL -ErrorAction SilentlyContinue
```

Explicitly allowlisted remote disposable database:

```powershell
$env:INGESTION_TEST_DATABASE_URL = "postgresql://postgres:...@db.example.test:5432/postgres"
$env:INGESTION_TEST_DATABASE_HOST_ALLOWLIST = "db.example.test"
$env:CONFIRM_DISPOSABLE_TEST_DB = "YES"
npm --workspace @confluendo/ingestion-platform test
Remove-Item Env:\INGESTION_TEST_DATABASE_URL,Env:\INGESTION_TEST_DATABASE_HOST_ALLOWLIST,Env:\CONFIRM_DISPOSABLE_TEST_DB -ErrorAction SilentlyContinue
```
