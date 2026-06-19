<#
Creates a logical Supabase database export for DR evidence and escape hatches.

This is not a replacement for Supabase physical backups or PITR. It does not
export Storage object bytes; it only exports database rows, including Storage
metadata tables.
#>
[CmdletBinding()]
param(
  [string]$DbUrl = $env:SUPABASE_DB_URL,
  [string]$TargetLabel = $env:DR_EXPORT_LABEL,
  [string]$OutDir = "backups/supabase",
  [switch]$Linked,
  [switch]$IncludeRoles
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not $TargetLabel) {
  throw "Set DR_EXPORT_LABEL (for example staging or prod) or pass -TargetLabel."
}

if (-not $Linked -and -not $DbUrl) {
  throw "Set SUPABASE_DB_URL or pass -Linked to export the linked project."
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$safeLabel = $TargetLabel -replace "[^A-Za-z0-9_.-]", "_"
$stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
$targetDir = Join-Path (Join-Path $repoRoot $OutDir) "$stamp-$safeLabel"
New-Item -ItemType Directory -Force -Path $targetDir | Out-Null

function Invoke-Dump {
  param(
    [Parameter(Mandatory = $true)][string]$File,
    [string[]]$ExtraArgs = @()
  )

  $args = @("db", "dump", "--file", $File)
  if ($Linked) {
    $args += "--linked"
  } else {
    $args += @("--db-url", $DbUrl)
  }
  $args += $ExtraArgs

  & supabase @args
  if ($LASTEXITCODE -ne 0) {
    throw "supabase db dump failed for $File"
  }
}

$schemaFile = Join-Path $targetDir "schema.sql"
$dataFile = Join-Path $targetDir "data.sql"
$manifestFile = Join-Path $targetDir "manifest.json"

Invoke-Dump -File $schemaFile
Invoke-Dump -File $dataFile -ExtraArgs @("--data-only", "--use-copy")

$roleFile = $null
if ($IncludeRoles) {
  $roleFile = Join-Path $targetDir "roles.sql"
  Invoke-Dump -File $roleFile -ExtraArgs @("--role-only")
}

$files = @("schema.sql", "data.sql")
if ($roleFile) {
  $files += "roles.sql"
}

$manifest = [ordered]@{
  created_at_utc = (Get-Date).ToUniversalTime().ToString("o")
  target_label = $TargetLabel
  source = if ($Linked) { "linked-project" } else { "SUPABASE_DB_URL" }
  files = $files
  storage_object_bytes_exported = $false
  storage_note = "Supabase database dumps include Storage metadata rows, not object bytes. Use Storage replication/export separately for media DR."
}

$manifest | ConvertTo-Json -Depth 5 | Set-Content -Path $manifestFile -Encoding UTF8

Write-Host "DR export created: $targetDir"
Write-Host "Files: schema.sql, data.sql, manifest.json"
if ($IncludeRoles) {
  Write-Host "Roles: roles.sql"
}
Write-Host "Reminder: upload this folder to the approved off-site backup location."
