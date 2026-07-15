param(
  [ValidateSet("Staging", "Production")]
  [string]$ControlEnvironment = "Staging",

  [string]$EnvironmentFile,

  [switch]$Execute,

  [string]$ProductionConfirmation
)

$ErrorActionPreference = "Stop"

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$webRoot = (Resolve-Path (Join-Path $scriptDirectory "..")).Path

if ($Execute -and $ControlEnvironment -eq "Production" -and $ProductionConfirmation -cne "PRODUCTION") {
  throw "Production runtime-role bootstrap requires -ProductionConfirmation PRODUCTION."
}

function Read-EnvironmentFileValue {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Name
  )

  $matches = @()
  foreach ($line in Get-Content -LiteralPath $Path) {
    $trimmed = $line.Trim()
    if (!$trimmed -or $trimmed.StartsWith("#")) { continue }
    if ($trimmed -match "^(?:export\s+)?$([regex]::Escape($Name))\s*=\s*(.*)$") {
      $matches += $Matches[1].Trim()
    }
  }
  if ($matches.Count -ne 1 -or [string]::IsNullOrWhiteSpace($matches[0])) {
    throw "Expected exactly one non-empty $Name entry in $Path."
  }

  $value = $matches[0]
  if ($value.Length -ge 2 -and (
    ($value.StartsWith('"') -and $value.EndsWith('"')) -or
    ($value.StartsWith("'") -and $value.EndsWith("'"))
  )) {
    return $value.Substring(1, $value.Length - 2)
  }
  return $value
}

if ([string]::IsNullOrWhiteSpace($EnvironmentFile)) {
  $EnvironmentFile = if ($ControlEnvironment -eq "Production") {
    Join-Path $webRoot ".env.production.local"
  } else {
    Join-Path $webRoot ".env.staging.local"
  }
}
if ($Execute -and !(Test-Path -LiteralPath $EnvironmentFile -PathType Leaf)) {
  throw "Missing trusted control profile: $EnvironmentFile"
}

$environmentNames = @(
  "CONFLUENDO_CONTROL_RUNTIME_BOOTSTRAP_OWNER_DATABASE_URL",
  "CONFLUENDO_CONTROL_RUNTIME_BOOTSTRAP_PROFILE_PATH",
  "CONFIRM_CONFLUENDO_CONTROL_RUNTIME_BOOTSTRAP",
  "CONFLUENDO_CONTROL_RUNTIME_BOOTSTRAP_CONFIRM_PRODUCTION"
)
$originalEnvironment = @{}
foreach ($name in $environmentNames) {
  $originalEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, "Process")
}

try {
  if ($Execute) {
    $ownerDatabaseUrl = Read-EnvironmentFileValue -Path $EnvironmentFile -Name "INGESTION_CONTROL_OWNER_DATABASE_URL"
    [Environment]::SetEnvironmentVariable("CONFLUENDO_CONTROL_RUNTIME_BOOTSTRAP_OWNER_DATABASE_URL", $ownerDatabaseUrl, "Process")
    [Environment]::SetEnvironmentVariable("CONFLUENDO_CONTROL_RUNTIME_BOOTSTRAP_PROFILE_PATH", $EnvironmentFile, "Process")
    [Environment]::SetEnvironmentVariable("CONFIRM_CONFLUENDO_CONTROL_RUNTIME_BOOTSTRAP", "YES", "Process")
  }
  if ($ControlEnvironment -eq "Production") {
    [Environment]::SetEnvironmentVariable("CONFLUENDO_CONTROL_RUNTIME_BOOTSTRAP_CONFIRM_PRODUCTION", "PRODUCTION", "Process")
  }

  Write-Host "Confluendo control runtime-role bootstrap"
  Write-Host "Control environment: $ControlEnvironment"
  Write-Host "Runtime role: confluendo_app"
  Write-Host "Profile: $EnvironmentFile"
  Write-Host "Mode: $(if ($Execute) { 'execute' } else { 'preview' })"
  Write-Host ""

  $nodeArguments = @("--control-environment", $ControlEnvironment.ToLowerInvariant())
  if ($Execute) { $nodeArguments += "--execute" }

  Push-Location -LiteralPath $webRoot
  try {
    & npm --workspace "@confluendo/ingestion-platform" run control:bootstrap-runtime-role -- -- @nodeArguments
    if ($LASTEXITCODE -ne 0) {
      throw "Control runtime-role bootstrap failed with exit code $LASTEXITCODE."
    }
  } finally {
    Pop-Location
  }
} finally {
  foreach ($name in $environmentNames) {
    [Environment]::SetEnvironmentVariable($name, $originalEnvironment[$name], "Process")
  }
}
