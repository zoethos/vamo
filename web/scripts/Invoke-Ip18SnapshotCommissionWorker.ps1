param(
  [ValidateSet("Staging", "Production")]
  [string]$ControlEnvironment = "Staging",

  [switch]$PreflightOnly,

  [switch]$Execute,

  [string]$WorkerId = "snapshot-commission-worker",

  [string]$WorkerRunKey
)

$ErrorActionPreference = "Stop"

if ($PreflightOnly -and $Execute) {
  throw "Choose either -PreflightOnly or -Execute, not both."
}
if (!$PreflightOnly -and !$Execute) {
  throw "Choose -PreflightOnly or -Execute. -Execute is required before the worker can claim a commissioning request."
}

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$webRoot = (Resolve-Path (Join-Path $scriptDirectory "..")).Path
$environmentSuffix = $ControlEnvironment.ToLowerInvariant()
$artifactProfile = Join-Path $webRoot ".env.$environmentSuffix.local"
$commissionProfile = Join-Path $webRoot ".env.snapshot-commission.$environmentSuffix.local"

function Read-EnvironmentFile {
  param([Parameter(Mandatory = $true)][string]$Path)

  if (!(Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Missing trusted worker environment file: $Path"
  }

  $values = @{}
  foreach ($line in Get-Content -LiteralPath $Path) {
    $trimmed = $line.Trim()
    if (!$trimmed -or $trimmed.StartsWith("#")) {
      continue
    }
    if ($trimmed -notmatch "^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$") {
      continue
    }

    $name = $Matches[1]
    if ($values.ContainsKey($name)) {
      throw "Duplicate environment entry for $name in $Path."
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

function Require-EnvironmentValue {
  param(
    [Parameter(Mandatory = $true)][hashtable]$Values,
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Path
  )

  if (!$Values.ContainsKey($Name) -or [string]::IsNullOrWhiteSpace($Values[$Name])) {
    throw "Missing $Name in trusted worker environment file: $Path"
  }
  return $Values[$Name]
}

function Set-ScopedEnvironmentValue {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Value,
    [Parameter(Mandatory = $true)][hashtable]$OriginalValues
  )

  if (!$OriginalValues.ContainsKey($Name)) {
    $OriginalValues[$Name] = [Environment]::GetEnvironmentVariable($Name, "Process")
  }
  [Environment]::SetEnvironmentVariable($Name, $Value, "Process")
}

$artifactValues = Read-EnvironmentFile -Path $artifactProfile
$commissionValues = Read-EnvironmentFile -Path $commissionProfile
$originalValues = @{}

try {
  $artifactNames = @(
    "CONFLUENDO_SNAPSHOT_ARTIFACT_STORE",
    "CONFLUENDO_SNAPSHOT_ARTIFACT_SUPABASE_PROJECT_REF",
    "CONFLUENDO_SNAPSHOT_ARTIFACT_SUPABASE_BUCKET",
    "CONFLUENDO_SNAPSHOT_ARTIFACT_SUPABASE_REGION",
    "CONFLUENDO_SNAPSHOT_ARTIFACT_SUPABASE_ACCESS_KEY_ID",
    "CONFLUENDO_SNAPSHOT_ARTIFACT_SUPABASE_SECRET_ACCESS_KEY"
  )
  foreach ($name in $artifactNames) {
    Set-ScopedEnvironmentValue -Name $name -Value (Require-EnvironmentValue -Values $artifactValues -Name $name -Path $artifactProfile) -OriginalValues $originalValues
  }

  $controlDatabaseUrl = Require-EnvironmentValue -Values $commissionValues -Name "INGESTION_CONTROL_DATABASE_URL" -Path $commissionProfile
  $portalToken = Require-EnvironmentValue -Values $commissionValues -Name "FSQ_OS_PLACES_PORTAL_ACCESS_TOKEN" -Path $commissionProfile
  $portalTokenExpiresAt = Require-EnvironmentValue -Values $commissionValues -Name "FSQ_OS_PLACES_PORTAL_ACCESS_TOKEN_EXPIRES_AT" -Path $commissionProfile
  Set-ScopedEnvironmentValue -Name "INGESTION_CONTROL_DATABASE_URL" -Value $controlDatabaseUrl -OriginalValues $originalValues
  Set-ScopedEnvironmentValue -Name "FSQ_OS_PLACES_PORTAL_ACCESS_TOKEN" -Value $portalToken -OriginalValues $originalValues
  Set-ScopedEnvironmentValue -Name "FSQ_OS_PLACES_PORTAL_ACCESS_TOKEN_EXPIRES_AT" -Value $portalTokenExpiresAt -OriginalValues $originalValues

  if ($commissionValues.ContainsKey("CONFLUENDO_CONTROL_ENVIRONMENT") -and
    $commissionValues["CONFLUENDO_CONTROL_ENVIRONMENT"].Trim().ToLowerInvariant() -ne $environmentSuffix) {
    throw "CONFLUENDO_CONTROL_ENVIRONMENT in $commissionProfile does not match $ControlEnvironment."
  }

  # DuckDB's HTTPS extensions use the Windows system trust store only when this is set.
  Set-ScopedEnvironmentValue -Name "NODE_USE_SYSTEM_CA" -Value "1" -OriginalValues $originalValues

  Write-Host "Confluendo snapshot commission worker"
  Write-Host "Control environment: $ControlEnvironment"
  Write-Host "Artifact store: Supabase Storage (profile loaded)"
  Write-Host "Portal token: configured and expiry metadata loaded"
  Write-Host "Windows system CA trust: enabled"
  Write-Host ""

  Push-Location -LiteralPath $webRoot
  try {
    npm --workspace @confluendo/ingestion-platform run ip18:artifact-store-preflight
    if ($LASTEXITCODE -ne 0) {
      throw "Snapshot artifact-store preflight failed with exit code $LASTEXITCODE."
    }

    if ($PreflightOnly) {
      Write-Host ""
      Write-Host "Preflight passed. No commissioning request was claimed, no FSQ query ran, and no artifact was written."
      return
    }

    Set-ScopedEnvironmentValue -Name "CONFIRM_CONFLUENDO_SNAPSHOT_COMMISSION_WORKER" -Value "YES" -OriginalValues $originalValues
    $workerArgs = @("--worker-id", $WorkerId)
    if (![string]::IsNullOrWhiteSpace($WorkerRunKey)) {
      $workerArgs += @("--worker-run-key", $WorkerRunKey)
    }

    Write-Host ""
    Write-Host "Executing one trusted worker cycle. It can claim only a console-recorded request."
    npm --workspace @confluendo/ingestion-platform run ip18:snapshot-commission-worker -- @workerArgs
    if ($LASTEXITCODE -ne 0) {
      throw "Snapshot commission worker failed with exit code $LASTEXITCODE. Review the safe error code above before submitting another request."
    }
  } finally {
    Pop-Location
  }
} finally {
  foreach ($name in $originalValues.Keys) {
    [Environment]::SetEnvironmentVariable($name, $originalValues[$name], "Process")
  }
}
