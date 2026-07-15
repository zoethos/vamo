param(
  [ValidateSet("Staging", "Production")]
  [string]$DefaultEnvironment = "Production",

  [string]$StagingEnvironmentFile,

  [string]$ProductionEnvironmentFile,

  [switch]$ValidateOnly
)

$ErrorActionPreference = "Stop"

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$webRoot = (Resolve-Path (Join-Path $scriptDirectory "..")).Path
$consoleRoot = Join-Path $webRoot "apps\confluendo-console"

if ([string]::IsNullOrWhiteSpace($StagingEnvironmentFile)) {
  $StagingEnvironmentFile = Join-Path $webRoot ".env.staging.local"
}
if ([string]::IsNullOrWhiteSpace($ProductionEnvironmentFile)) {
  $ProductionEnvironmentFile = Join-Path $webRoot ".env.production.local"
}

function Read-EnvironmentFile {
  param([Parameter(Mandatory = $true)][string]$Path)

  if (!(Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Missing control-workspace environment file: $Path"
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
    [Parameter(Mandatory = $true)][string[]]$Names,
    [Parameter(Mandatory = $true)][string]$ProfileName,
    [Parameter(Mandatory = $true)][string]$Path
  )

  foreach ($name in $Names) {
    if ($Values.ContainsKey($name) -and ![string]::IsNullOrWhiteSpace($Values[$name])) {
      return $Values[$name]
    }
  }

  throw "Missing $($Names -join ' or ') in $ProfileName control-workspace profile: $Path"
}

function Set-ProcessEnvironmentValue {
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

function Load-ControlWorkspaceProfile {
  param(
    [ValidateSet("Staging", "Production")][string]$EnvironmentName,
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][hashtable]$OriginalValues
  )

  $values = Read-EnvironmentFile -Path $Path
  $prefix = "CONFLUENDO_CONTROL_$($EnvironmentName.ToUpperInvariant())"
  $supabaseUrl = Require-EnvironmentValue -Values $values -Names @("NEXT_PUBLIC_SUPABASE_URL") -ProfileName $EnvironmentName -Path $Path
  $supabasePublishableKey = Require-EnvironmentValue -Values $values -Names @("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY", "NEXT_PUBLIC_SUPABASE_ANON_KEY") -ProfileName $EnvironmentName -Path $Path
  $controlDatabaseUrl = Require-EnvironmentValue -Values $values -Names @("INGESTION_CONTROL_DATABASE_URL") -ProfileName $EnvironmentName -Path $Path

  Set-ProcessEnvironmentValue -Name "${prefix}_SUPABASE_URL" -Value $supabaseUrl -OriginalValues $OriginalValues
  Set-ProcessEnvironmentValue -Name "${prefix}_SUPABASE_PUBLISHABLE_KEY" -Value $supabasePublishableKey -OriginalValues $OriginalValues
  Set-ProcessEnvironmentValue -Name "${prefix}_DATABASE_URL" -Value $controlDatabaseUrl -OriginalValues $OriginalValues

  if ($EnvironmentName -eq "Production") {
    $optionalMappings = @{
      "VAMO_PLACE_CACHE_DATABASE_URL" = "${prefix}_VAMO_PLACE_CACHE_DATABASE_URL"
      "VAMO_PRODUCTION_INBOX_TELEMETRY_DATABASE_URL" = "${prefix}_VAMO_PRODUCTION_INBOX_TELEMETRY_DATABASE_URL"
      "VAMO_PRODUCTION_INBOX_APPLY_DATABASE_URL" = "${prefix}_VAMO_PRODUCTION_INBOX_APPLY_DATABASE_URL"
      "VAMO_PRODUCTION_INBOX_WRITER_DATABASE_URL" = "${prefix}_VAMO_PRODUCTION_INBOX_WRITER_DATABASE_URL"
      "VAMO_PRODUCTION_INBOX_ENVIRONMENT" = "${prefix}_VAMO_PRODUCTION_INBOX_ENVIRONMENT"
      "INGESTION_ADMIN_API_TOKEN" = "${prefix}_INGESTION_ADMIN_API_TOKEN"
    }
    foreach ($sourceName in $optionalMappings.Keys) {
      if ($values.ContainsKey($sourceName) -and ![string]::IsNullOrWhiteSpace($values[$sourceName])) {
        Set-ProcessEnvironmentValue -Name $optionalMappings[$sourceName] -Value $values[$sourceName] -OriginalValues $OriginalValues
      }
    }
  }

  Write-Host "Loaded $EnvironmentName control workspace profile: Supabase Auth and control DB configured."
}

if (!(Test-Path -LiteralPath (Join-Path $webRoot "package.json"))) {
  throw "Missing web package root: $webRoot"
}
if (!(Test-Path -LiteralPath (Join-Path $consoleRoot "package.json"))) {
  throw "Missing Confluendo console app: $consoleRoot"
}

$originalValues = @{}
try {
  Load-ControlWorkspaceProfile -EnvironmentName "Staging" -Path $StagingEnvironmentFile -OriginalValues $originalValues
  Load-ControlWorkspaceProfile -EnvironmentName "Production" -Path $ProductionEnvironmentFile -OriginalValues $originalValues
  Set-ProcessEnvironmentValue -Name "CONFLUENDO_CONTROL_DEFAULT_ENVIRONMENT" -Value $DefaultEnvironment.ToLowerInvariant() -OriginalValues $originalValues

  if ($ValidateOnly) {
    Write-Host "Both control workspace profiles are valid. No console server was started."
    return
  }

  Write-Host ""
  Write-Host "Starting Confluendo console with switchable control workspaces"
  Write-Host "Default workspace: $DefaultEnvironment"
  Write-Host "Console: http://localhost:4373/admin/ingestion"
  Write-Host "The browser receives only the selected Supabase public configuration. Database and Vamo credentials remain server-only."
  Write-Host "Press Ctrl+C to stop the server; this script then restores its process environment."
  Write-Host ""

  Push-Location -LiteralPath $webRoot
  try {
    npm --workspace @confluendo/console run dev
    if ($LASTEXITCODE -ne 0) {
      throw "Confluendo console exited with code $LASTEXITCODE."
    }
  } finally {
    Pop-Location
  }
} finally {
  foreach ($name in $originalValues.Keys) {
    [Environment]::SetEnvironmentVariable($name, $originalValues[$name], "Process")
  }
}
