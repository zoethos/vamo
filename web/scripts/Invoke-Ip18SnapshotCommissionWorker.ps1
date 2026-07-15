[CmdletBinding()]
param(
  [ValidateSet("Staging", "Production")]
  [string]$ControlEnvironment = "Staging",

  [switch]$Execute,

  [string]$WorkerId,

  [string]$ArtifactEnvironmentFile,

  [string]$WorkerEnvironmentFile
)

$ErrorActionPreference = "Stop"

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$webRoot = (Resolve-Path (Join-Path $scriptDirectory "..")).Path
$platformPackage = Join-Path $webRoot "packages\ingestion-platform"

if (!(Test-Path -LiteralPath $platformPackage)) {
  throw "Missing ingestion-platform package: $platformPackage"
}

. (Join-Path $scriptDirectory "ConfluendoTrustedEnvironment.ps1")

$environmentSuffix = if ($ControlEnvironment -eq "Production") { "production" } else { "staging" }
if ([string]::IsNullOrWhiteSpace($ArtifactEnvironmentFile)) {
  $ArtifactEnvironmentFile = Join-Path $webRoot ".env.$environmentSuffix.local"
}
if ([string]::IsNullOrWhiteSpace($WorkerEnvironmentFile)) {
  $WorkerEnvironmentFile = Join-Path $webRoot ".env.snapshot-commission.$environmentSuffix.local"
}
if ([string]::IsNullOrWhiteSpace($WorkerId)) {
  $WorkerId = "confluendo-snapshot-commission-$environmentSuffix"
}

$artifactEnvironmentNames = @(
  "CONFLUENDO_SNAPSHOT_ARTIFACT_STORE",
  "CONFLUENDO_SNAPSHOT_ARTIFACT_SUPABASE_PROJECT_REF",
  "CONFLUENDO_SNAPSHOT_ARTIFACT_SUPABASE_BUCKET",
  "CONFLUENDO_SNAPSHOT_ARTIFACT_SUPABASE_REGION",
  "CONFLUENDO_SNAPSHOT_ARTIFACT_SUPABASE_ACCESS_KEY_ID",
  "CONFLUENDO_SNAPSHOT_ARTIFACT_SUPABASE_SECRET_ACCESS_KEY"
)
$workerEnvironmentNames = @(
  "INGESTION_CONTROL_DATABASE_URL",
  "FSQ_OS_PLACES_CATALOG_SERVICE_API_KEY",
  "FSQ_OS_PLACES_CATALOG_TOKEN"
)
$artifactValues = Read-ConfluendoTrustedEnvironmentFile -Path $ArtifactEnvironmentFile -AllowedNames $artifactEnvironmentNames
$workerValues = Read-ConfluendoTrustedEnvironmentFile -Path $WorkerEnvironmentFile -AllowedNames $workerEnvironmentNames

$requiredValues = @{}
foreach ($name in $artifactEnvironmentNames) {
  $requiredValues[$name] = $artifactValues[$name]
}
foreach ($name in $workerEnvironmentNames) {
  $requiredValues[$name] = $workerValues[$name]
}
if ([string]::IsNullOrWhiteSpace($requiredValues["FSQ_OS_PLACES_CATALOG_SERVICE_API_KEY"])) {
  $requiredValues["FSQ_OS_PLACES_CATALOG_SERVICE_API_KEY"] = $requiredValues["FSQ_OS_PLACES_CATALOG_TOKEN"]
}
if (![string]::IsNullOrWhiteSpace($requiredValues["FSQ_OS_PLACES_CATALOG_TOKEN"])) {
  Write-Warning "FSQ_OS_PLACES_CATALOG_TOKEN is deprecated; rename it to FSQ_OS_PLACES_CATALOG_SERVICE_API_KEY."
}
if ($requiredValues.ContainsKey("FSQ_OS_PLACES_CATALOG_TOKEN")) {
  $requiredValues.Remove("FSQ_OS_PLACES_CATALOG_TOKEN")
}
foreach ($name in $requiredValues.Keys) {
  if ([string]::IsNullOrWhiteSpace($requiredValues[$name])) {
    throw "$name is required in the trusted worker environment files."
  }
}
if ($requiredValues["CONFLUENDO_SNAPSHOT_ARTIFACT_STORE"].Trim().ToLowerInvariant() -ne "supabase") {
  throw "CONFLUENDO_SNAPSHOT_ARTIFACT_STORE must be supabase for the hosted commission worker."
}

Write-Host "Confluendo snapshot commission worker"
Write-Host "Control environment: $ControlEnvironment"
Write-Host "Worker id: $WorkerId"
Write-Host "Artifact bucket: $($requiredValues['CONFLUENDO_SNAPSHOT_ARTIFACT_SUPABASE_BUCKET'])"
Write-Host "Worker request: claims at most one pending commission request."
Write-Host ""

if (!$Execute) {
  Write-Host "Configuration validated. No commission worker was run."
  Write-Host "Use -Execute only after an admin has requested a bounded snapshot commission in the Queue workflow."
  exit 0
}

$temporaryEnvironmentNames = @(
  $artifactEnvironmentNames +
  "INGESTION_CONTROL_DATABASE_URL" +
  "FSQ_OS_PLACES_CATALOG_SERVICE_API_KEY" +
  "FSQ_OS_PLACES_CATALOG_TOKEN" +
  "CONFIRM_CONFLUENDO_SNAPSHOT_COMMISSION_WORKER"
)
$originalEnvironment = @{}
foreach ($name in $temporaryEnvironmentNames) {
  $originalEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, "Process")
}

try {
  foreach ($name in $artifactEnvironmentNames) {
    [Environment]::SetEnvironmentVariable($name, $artifactValues[$name], "Process")
  }
  [Environment]::SetEnvironmentVariable(
    "INGESTION_CONTROL_DATABASE_URL",
    $requiredValues["INGESTION_CONTROL_DATABASE_URL"],
    "Process"
  )
  [Environment]::SetEnvironmentVariable(
    "FSQ_OS_PLACES_CATALOG_SERVICE_API_KEY",
    $requiredValues["FSQ_OS_PLACES_CATALOG_SERVICE_API_KEY"],
    "Process"
  )
  [Environment]::SetEnvironmentVariable("CONFIRM_CONFLUENDO_SNAPSHOT_COMMISSION_WORKER", "YES", "Process")

  Push-Location -LiteralPath $webRoot
  try {
    Write-Host "=== Verify artifact store access ==="
    npm --workspace @confluendo/ingestion-platform run ip18:artifact-store-preflight
    if ($LASTEXITCODE -ne 0) {
      throw "Snapshot artifact-store preflight failed with exit code $LASTEXITCODE."
    }

    Write-Host ""
    Write-Host "=== Run one snapshot commission worker cycle ==="
    npm --workspace @confluendo/ingestion-platform run ip18:snapshot-commission-worker -- --worker-id $WorkerId
    if ($LASTEXITCODE -ne 0) {
      throw "Snapshot commission worker failed with exit code $LASTEXITCODE."
    }
  } finally {
    Pop-Location
  }
} finally {
  foreach ($name in $temporaryEnvironmentNames) {
    [Environment]::SetEnvironmentVariable($name, $originalEnvironment[$name], "Process")
  }
}
