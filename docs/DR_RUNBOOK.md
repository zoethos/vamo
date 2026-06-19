# Disaster Recovery Runbook

Cycle 2 DR has two layers:

- **Primary recovery:** Supabase physical backups and PITR for the Postgres
  database.
- **Independent evidence:** repo-local logical exports that can be replayed into
  a disposable non-prod database for restore drills and vendor escape planning.

Supabase database backups do not restore Storage object bytes. They cover the
database, including Storage metadata, but media files need their own export or
replication path before public launch.

## Preconditions

- Supabase Pro is enabled for the production project.
- PITR is enabled on at least Small compute.
- A staging or disposable restore-drill project exists.
- Off-site backup storage exists outside Supabase.
- `supabase` CLI is authenticated.
- `psql` is installed for local restore drills.

References:

- Supabase backups: https://supabase.com/docs/guides/platform/backups
- Supabase `db dump`: https://supabase.com/docs/reference/cli/supabase-db-dump

## Daily Backup Check

```powershell
supabase backups list --project-ref <prod-ref>
```

Pass criteria:

- at least one recent backup is listed
- PITR is enabled and the recovery window is visible in the dashboard
- the project has no dashboard warnings that would block restore

## Logical Export

Prefer a direct database URL from the dashboard or the linked project. Do not
commit generated dumps; `backups/` is gitignored.

```powershell
$env:DR_EXPORT_LABEL = "prod"
$env:SUPABASE_DB_URL = "<percent-encoded-postgres-url>"
.\tool\dr_export.ps1
```

For a linked project:

```powershell
$env:DR_EXPORT_LABEL = "staging"
.\tool\dr_export.ps1 -Linked
```

Upload the generated `backups/supabase/<timestamp-label>/` folder to the
approved off-site backup location.

## Restore Drill

Use a disposable non-prod target. The script never drops an existing database,
so the target should be empty.

```powershell
$env:DR_RESTORE_TARGET_DB_URL = "<restore-drill-postgres-url>"
.\tool\dr_restore_drill.ps1 `
  -DumpDir "backups/supabase/<timestamp-label>" `
  -ConfirmNonProdTarget
```

When the dry run looks correct:

```powershell
.\tool\dr_restore_drill.ps1 `
  -DumpDir "backups/supabase/<timestamp-label>" `
  -ConfirmNonProdTarget `
  -Execute
```

After replay, run app smoke checks against the restore target:

- can list profiles and trips
- can read representative trip members, expenses, and notifications
- RLS still blocks cross-user writes
- migration history is inspectable

## PITR Incident Path

Use PITR only after a named incident and a selected recovery timestamp.

```powershell
$timestamp = [DateTimeOffset]::Parse("2026-06-20T10:00:00Z").ToUnixTimeSeconds()
supabase backups restore --project-ref <prod-ref> --timestamp $timestamp
```

Record:

- incident ID
- chosen recovery timestamp
- approver
- CLI command used
- post-restore smoke results
- user-visible data loss window

## Open DR Gap

Storage object bytes are not covered by database backups or these logical dump
scripts. Before public v1, add a Storage export/replication procedure for:

- trip media
- memories/capture uploads
- profile avatars
