param(
  [ValidateSet("Staging", "Production")]
  [string]$ControlEnvironment = "Staging",

  [Parameter(Mandatory = $true)]
  [string]$Email,

  [Parameter(Mandatory = $true)]
  [string]$AuditReason,

  [string]$EnvironmentFile,

  [switch]$Execute,

  [string]$ProductionConfirmation
)

$ErrorActionPreference = "Stop"

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$webRoot = (Resolve-Path (Join-Path $scriptDirectory "..")).Path
$platformPackage = Join-Path $webRoot "packages\ingestion-platform"
$defaultEnvironmentFile = if ($ControlEnvironment -eq "Production") {
  Join-Path $webRoot ".env.production.local"
} else {
  Join-Path $webRoot ".env.staging.local"
}

if (!(Test-Path -LiteralPath $platformPackage)) {
  throw "Missing ingestion-platform package: $platformPackage"
}
if ([string]::IsNullOrWhiteSpace($EnvironmentFile)) {
  $EnvironmentFile = $defaultEnvironmentFile
}
if (!(Test-Path -LiteralPath $EnvironmentFile -PathType Leaf)) {
  throw "Missing trusted provisioning environment file: $EnvironmentFile"
}
if ($Execute -and $ControlEnvironment -eq "Production" -and $ProductionConfirmation -cne "PRODUCTION") {
  throw "Production provisioning requires -ProductionConfirmation PRODUCTION."
}

function Read-EnvironmentFile {
  param([Parameter(Mandatory = $true)][string]$Path)

  $allowedNames = @{
    "NEXT_PUBLIC_SUPABASE_URL" = $true
    "CONFLUENDO_CONTROL_SUPABASE_SECRET_KEY" = $true
    "INGESTION_CONTROL_OWNER_DATABASE_URL" = $true
  }
  $values = @{}
  foreach ($line in Get-Content -LiteralPath $Path) {
    $trimmed = $line.Trim()
    if (!$trimmed -or $trimmed.StartsWith("#")) { continue }
    if ($trimmed -notmatch "^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$") { continue }

    $name = $Matches[1]
    if (!$allowedNames.ContainsKey($name)) { continue }
    if ($values.ContainsKey($name)) {
      throw "Duplicate trusted provisioning entry for $name in $Path."
    }

    $value = $Matches[2].Trim()
    if ($value.Length -ge 2 -and (
      ($value.StartsWith('"') -and $value.EndsWith('"')) -or
      ($value.StartsWith("'") -and $value.EndsWith("'"))
    )) {
      $value = $value.Substring(1, $value.Length - 2)
    }
    $values[$name] = $value
  }
  return $values
}

function Require-Value {
  param(
    [Parameter(Mandatory = $true)][hashtable]$Values,
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Path
  )
  if (!$Values.ContainsKey($Name) -or [string]::IsNullOrWhiteSpace($Values[$Name])) {
    throw "Missing $Name in trusted provisioning profile: $Path"
  }
  return $Values[$Name]
}

$values = Read-EnvironmentFile -Path $EnvironmentFile
$supabaseUrl = Require-Value -Values $values -Name "NEXT_PUBLIC_SUPABASE_URL" -Path $EnvironmentFile
$supabaseSecretKey = Require-Value -Values $values -Name "CONFLUENDO_CONTROL_SUPABASE_SECRET_KEY" -Path $EnvironmentFile
$ownerDatabaseUrl = Require-Value -Values $values -Name "INGESTION_CONTROL_OWNER_DATABASE_URL" -Path $EnvironmentFile

$environmentNames = @(
  "CONFLUENDO_CONTROL_ADMIN_PROVISION_SUPABASE_URL",
  "CONFLUENDO_CONTROL_ADMIN_PROVISION_SUPABASE_SECRET_KEY",
  "CONFLUENDO_CONTROL_ADMIN_PROVISION_DATABASE_URL",
  "CONFIRM_CONFLUENDO_CONTROL_ADMIN_PROVISION",
  "CONFLUENDO_CONTROL_ADMIN_PROVISION_CONFIRM_PRODUCTION"
)
$originalEnvironment = @{}
foreach ($name in $environmentNames) {
  $originalEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, "Process")
}

try {
  [Environment]::SetEnvironmentVariable("CONFLUENDO_CONTROL_ADMIN_PROVISION_SUPABASE_URL", $supabaseUrl, "Process")
  [Environment]::SetEnvironmentVariable("CONFLUENDO_CONTROL_ADMIN_PROVISION_SUPABASE_SECRET_KEY", $supabaseSecretKey, "Process")
  [Environment]::SetEnvironmentVariable("CONFLUENDO_CONTROL_ADMIN_PROVISION_DATABASE_URL", $ownerDatabaseUrl, "Process")
  if ($Execute) {
    [Environment]::SetEnvironmentVariable("CONFIRM_CONFLUENDO_CONTROL_ADMIN_PROVISION", "YES", "Process")
  }
  if ($ControlEnvironment -eq "Production") {
    [Environment]::SetEnvironmentVariable("CONFLUENDO_CONTROL_ADMIN_PROVISION_CONFIRM_PRODUCTION", "PRODUCTION", "Process")
  }

  Write-Host "Confluendo Vamo console-admin provisioning"
  Write-Host "Control environment: $ControlEnvironment"
  Write-Host "Project: vamo"
  Write-Host "Role: admin (MFA required)"
  Write-Host "Mode: $(if ($Execute) { 'execute' } else { 'preview' })"
  Write-Host ""

  $nodeArguments = @(
    "--email", $Email,
    "--audit-reason", $AuditReason,
    "--control-environment", $ControlEnvironment.ToLowerInvariant()
  )
  if ($Execute) { $nodeArguments += "--execute" }

  Push-Location -LiteralPath $webRoot
  try {
    # npm v11 consumes one delimiter before a chained script; the second sends
    # the named arguments through to Node unchanged.
    & npm --workspace "@confluendo/ingestion-platform" run control:provision-vamo-admin -- -- @nodeArguments
    if ($LASTEXITCODE -ne 0) {
      throw "Control-admin provisioning failed with exit code $LASTEXITCODE."
    }
  } finally {
    Pop-Location
  }
} finally {
  foreach ($name in $environmentNames) {
    [Environment]::SetEnvironmentVariable($name, $originalEnvironment[$name], "Process")
  }
}
