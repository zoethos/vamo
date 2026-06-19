<#
Replays a logical DR export into a disposable, non-production Postgres target.

This script is intentionally conservative: it never drops or resets a database,
and it refuses the known production project ref. Use an empty restore-drill
database or Supabase preview project as the target.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$DumpDir,
  [string]$TargetDbUrl = $env:DR_RESTORE_TARGET_DB_URL,
  [switch]$Execute,
  [switch]$ConfirmNonProdTarget
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$knownProdSupabaseRef = "mjercplkmuoctdklosyy"

if (-not $TargetDbUrl) {
  throw "Set DR_RESTORE_TARGET_DB_URL or pass -TargetDbUrl."
}

if ($TargetDbUrl.Contains($knownProdSupabaseRef)) {
  throw "Refusing to restore into the known production project ref."
}

if (-not $ConfirmNonProdTarget) {
  throw "Pass -ConfirmNonProdTarget after verifying the target is disposable non-prod."
}

$dumpPath = (Resolve-Path $DumpDir).Path
$schemaFile = Join-Path $dumpPath "schema.sql"
$dataFile = Join-Path $dumpPath "data.sql"

foreach ($file in @($schemaFile, $dataFile)) {
  if (-not (Test-Path -LiteralPath $file)) {
    throw "Missing dump file: $file"
  }
}

Write-Host "Restore drill target: [redacted connection string]"
Write-Host "Dump directory: $dumpPath"
Write-Host "Plan:"
Write-Host "  psql <target-db-url> -v ON_ERROR_STOP=1 -f $schemaFile"
Write-Host "  psql <target-db-url> -v ON_ERROR_STOP=1 -f $dataFile"

if (-not $Execute) {
  Write-Host "Dry run only. Re-run with -Execute to replay into the target."
  exit 0
}

$psql = Get-Command psql -ErrorAction Stop

foreach ($file in @($schemaFile, $dataFile)) {
  & $psql.Path $TargetDbUrl "-v" "ON_ERROR_STOP=1" "-f" $file
  if ($LASTEXITCODE -ne 0) {
    throw "psql restore failed for $file"
  }
}

Write-Host "Restore drill replay complete. Run smoke checks against the target now."
