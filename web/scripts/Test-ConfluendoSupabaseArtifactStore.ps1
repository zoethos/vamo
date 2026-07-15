param(
  [ValidateSet("Staging", "Production")]
  [string]$ControlEnvironment = "Staging",

  [string]$ProjectRef,

  [string]$EnvironmentFile,

  [string]$Bucket,

  [string]$Region,

  [string]$AccessKeyId,

  [SecureString]$SecretAccessKey
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

. (Join-Path $scriptDirectory "ConfluendoTrustedEnvironment.ps1")

if ([string]::IsNullOrWhiteSpace($EnvironmentFile)) {
  $EnvironmentFile = $defaultEnvironmentFile
}
$environmentNames = @(
  "CONFLUENDO_SNAPSHOT_ARTIFACT_STORE",
  "CONFLUENDO_SNAPSHOT_ARTIFACT_SUPABASE_PROJECT_REF",
  "CONFLUENDO_SNAPSHOT_ARTIFACT_SUPABASE_BUCKET",
  "CONFLUENDO_SNAPSHOT_ARTIFACT_SUPABASE_REGION",
  "CONFLUENDO_SNAPSHOT_ARTIFACT_SUPABASE_ACCESS_KEY_ID",
  "CONFLUENDO_SNAPSHOT_ARTIFACT_SUPABASE_SECRET_ACCESS_KEY"
)
$environmentValues = Read-ConfluendoTrustedEnvironmentFile -Path $EnvironmentFile -AllowedNames $environmentNames

if ([string]::IsNullOrWhiteSpace($ProjectRef)) {
  $ProjectRef = $environmentValues["CONFLUENDO_SNAPSHOT_ARTIFACT_SUPABASE_PROJECT_REF"]
}
if ($ProjectRef -notmatch "^[a-z0-9]{20}$") {
  throw "CONFLUENDO_SNAPSHOT_ARTIFACT_SUPABASE_PROJECT_REF must be a 20-character lowercase project reference."
}
if ([string]::IsNullOrWhiteSpace($Bucket)) {
  $Bucket = $environmentValues["CONFLUENDO_SNAPSHOT_ARTIFACT_SUPABASE_BUCKET"]
}
if ([string]::IsNullOrWhiteSpace($Region)) {
  $Region = $environmentValues["CONFLUENDO_SNAPSHOT_ARTIFACT_SUPABASE_REGION"]
}
if ([string]::IsNullOrWhiteSpace($AccessKeyId)) {
  $AccessKeyId = $environmentValues["CONFLUENDO_SNAPSHOT_ARTIFACT_SUPABASE_ACCESS_KEY_ID"]
}

$artifactStoreKind = $environmentValues["CONFLUENDO_SNAPSHOT_ARTIFACT_STORE"]
if ([string]::IsNullOrWhiteSpace($artifactStoreKind) -or $artifactStoreKind.Trim().ToLowerInvariant() -ne "supabase") {
  throw "CONFLUENDO_SNAPSHOT_ARTIFACT_STORE in $EnvironmentFile must be supabase."
}
if ([string]::IsNullOrWhiteSpace($Bucket)) {
  throw "CONFLUENDO_SNAPSHOT_ARTIFACT_SUPABASE_BUCKET is required in $EnvironmentFile."
}
if ([string]::IsNullOrWhiteSpace($Region)) {
  throw "CONFLUENDO_SNAPSHOT_ARTIFACT_SUPABASE_REGION is required in $EnvironmentFile."
}

if ([string]::IsNullOrWhiteSpace($AccessKeyId)) {
  $AccessKeyId = Read-Host "Supabase S3 access key ID for $ControlEnvironment (not found in $EnvironmentFile)"
}
if ([string]::IsNullOrWhiteSpace($AccessKeyId)) {
  throw "A Supabase S3 access key ID is required."
}
if ($null -eq $SecretAccessKey) {
  $fileSecret = $environmentValues["CONFLUENDO_SNAPSHOT_ARTIFACT_SUPABASE_SECRET_ACCESS_KEY"]
  if ([string]::IsNullOrWhiteSpace($fileSecret)) {
    $SecretAccessKey = Read-Host "Supabase S3 secret access key for $ControlEnvironment (not found in $EnvironmentFile)" -AsSecureString
  }
}

$originalEnvironment = @{}
foreach ($name in $environmentNames) {
  $originalEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, "Process")
}

$secretBstr = [IntPtr]::Zero
$plainSecret = $null
try {
  $plainSecret = $environmentValues["CONFLUENDO_SNAPSHOT_ARTIFACT_SUPABASE_SECRET_ACCESS_KEY"]
  if ([string]::IsNullOrWhiteSpace($plainSecret)) {
    if ($null -eq $SecretAccessKey) {
      throw "A Supabase S3 secret access key is required."
    }
    $secretBstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecretAccessKey)
    $plainSecret = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($secretBstr)
  }

  [Environment]::SetEnvironmentVariable("CONFLUENDO_SNAPSHOT_ARTIFACT_STORE", "supabase", "Process")
  [Environment]::SetEnvironmentVariable("CONFLUENDO_SNAPSHOT_ARTIFACT_SUPABASE_PROJECT_REF", $ProjectRef, "Process")
  [Environment]::SetEnvironmentVariable("CONFLUENDO_SNAPSHOT_ARTIFACT_SUPABASE_BUCKET", $Bucket, "Process")
  [Environment]::SetEnvironmentVariable("CONFLUENDO_SNAPSHOT_ARTIFACT_SUPABASE_REGION", $Region, "Process")
  [Environment]::SetEnvironmentVariable("CONFLUENDO_SNAPSHOT_ARTIFACT_SUPABASE_ACCESS_KEY_ID", $AccessKeyId, "Process")
  [Environment]::SetEnvironmentVariable("CONFLUENDO_SNAPSHOT_ARTIFACT_SUPABASE_SECRET_ACCESS_KEY", $plainSecret, "Process")

  Write-Host "Confluendo Supabase Storage preflight"
  Write-Host "Control environment: $ControlEnvironment"
  Write-Host "Bucket: $Bucket"
  Write-Host "Operation: HeadBucket only; no snapshot objects are read or written."
  Write-Host ""

  Push-Location -LiteralPath $webRoot
  try {
    npm --workspace @confluendo/ingestion-platform run ip18:artifact-store-preflight
    if ($LASTEXITCODE -ne 0) {
      throw "Snapshot artifact-store preflight failed with exit code $LASTEXITCODE."
    }
  } finally {
    Pop-Location
  }
} finally {
  if ($secretBstr -ne [IntPtr]::Zero) {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($secretBstr)
  }
  $plainSecret = $null

  foreach ($name in $environmentNames) {
    [Environment]::SetEnvironmentVariable($name, $originalEnvironment[$name], "Process")
  }
}
