param(
  [ValidateSet("Instructions", "Status", "PrepareDryRun", "ExecuteWave")]
  [string]$Mode = "Instructions",

  [string[]]$UnitKey = @(
    "vamo-place-intelligence:paris-france:landmark",
    "vamo-place-intelligence:barcelona-spain:landmark"
  ),

  [int]$ExpectedInsertCount = 2,
  [int]$DryRunMaxUnits = 0,
  [string]$DryRunAuditId = "",
  [string]$DryRunExecutionKey = "",
  [string]$DryRunAuditReason = "Prepare fixed IP-18.4 dry-run reports for the next staging-canary wave",
  [switch]$SkipReset,

  [string]$ApprovalAuditId = "",
  [string]$WaveKey = "",
  [int]$WaveMaxUnits = 1,
  [int]$WaveMaxRows = 2,
  [string]$WaveAuditReason = "Execute fixed IP-18.5 ramp-gated 1-unit Vamo staging wave",

  [switch]$NoBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$WebRoot = Split-Path -Parent $ScriptRoot
$PackageRoot = Join-Path $WebRoot "packages\ingestion-platform"

function Show-Instructions {
  Write-Host "IP-18 staging-wave operator helper"
  Write-Host ""
  Write-Host "1. Prepare control-plane dry-run reports:"
  Write-Host "   .\scripts\Invoke-Ip18StagingWaveCycle.ps1 -Mode PrepareDryRun"
  Write-Host ""
  Write-Host "2. Approve a fresh wave in /admin/ingestion:"
  Write-Host "   Max units: 1"
  Write-Host "   Max rows: 2"
  Write-Host ""
  Write-Host "3. Execute the approved wave:"
  Write-Host "   .\scripts\Invoke-Ip18StagingWaveCycle.ps1 -Mode ExecuteWave -ApprovalAuditId <id>"
  Write-Host ""
  Write-Host "Useful read-only check:"
  Write-Host "   .\scripts\Invoke-Ip18StagingWaveCycle.ps1 -Mode Status"
  Write-Host ""
  Write-Host "The helper never creates dashboard approvals. MFA/AAL2 approval remains manual."
}

function Remove-WrappingQuotes {
  param([string]$Value)

  $trimmed = $Value.Trim()
  if (($trimmed.StartsWith('"') -and $trimmed.EndsWith('"')) -or
      ($trimmed.StartsWith("'") -and $trimmed.EndsWith("'"))) {
    return $trimmed.Substring(1, $trimmed.Length - 2)
  }

  return $trimmed
}

function Import-DotEnv {
  param([Parameter(Mandatory = $true)][string]$Path)

  if (!(Test-Path -LiteralPath $Path)) {
    Write-Host "Skipping missing env file: $Path"
    return
  }

  Get-Content -LiteralPath $Path | ForEach-Object {
    $line = $_.Trim()
    if (!$line -or $line.StartsWith("#")) { return }

    $idx = $line.IndexOf("=")
    if ($idx -lt 1) { return }

    $key = $line.Substring(0, $idx).Trim()
    $value = $line.Substring($idx + 1).Trim()

    if (($value.StartsWith('"') -and $value.EndsWith('"')) -or
        ($value.StartsWith("'") -and $value.EndsWith("'"))) {
      $value = $value.Substring(1, $value.Length - 2)
    }

    [Environment]::SetEnvironmentVariable($key, $value, "Process")
  }
}

function Import-OperatorEnv {
  Import-DotEnv (Join-Path $WebRoot "apps\confluendo-console\.env.local")
  Import-DotEnv (Join-Path $WebRoot ".env.canary.local")
  Import-DotEnv (Join-Path $WebRoot "apps\confluendo-console\.env.canary.local")
  Import-DotEnv "Z:\vamo\staging.env.local"
}

function Assert-ControlDsn {
  if (!$env:INGESTION_CONTROL_DATABASE_URL) {
    throw "Missing INGESTION_CONTROL_DATABASE_URL. Expected it in $WebRoot\apps\confluendo-console\.env.local."
  }

  $uri = [Uri]$env:INGESTION_CONTROL_DATABASE_URL
  Write-Host "Control DB host: $($uri.Host)"
}

function Ensure-VamoStagingCanaryAppDsn {
  $projectRef = "sfwziwcuyctxvidivnsh"
  $poolerHost = "aws-1-eu-central-1.pooler.supabase.com"
  $canaryRole = "vamo_canary_app"
  $poolerUser = "$canaryRole.$projectRef"

  if (!$env:VAMO_STAGING_CANARY_APP_DATABASE_URL -and $env:VAMO_STAGING_CANARY_DB_PASSWORD) {
    $encodedPassword = [Uri]::EscapeDataString($env:VAMO_STAGING_CANARY_DB_PASSWORD)
    $env:VAMO_STAGING_CANARY_APP_DATABASE_URL = "postgresql://${poolerUser}:${encodedPassword}@${poolerHost}:5432/postgres"
    Write-Host "Derived VAMO_STAGING_CANARY_APP_DATABASE_URL from VAMO_STAGING_CANARY_DB_PASSWORD."
  }

  if (!$env:VAMO_STAGING_CANARY_APP_DATABASE_URL) {
    throw "Missing VAMO_STAGING_CANARY_APP_DATABASE_URL or VAMO_STAGING_CANARY_DB_PASSWORD."
  }

  $uri = [Uri]$env:VAMO_STAGING_CANARY_APP_DATABASE_URL
  $userName = ($uri.UserInfo -split ":")[0]
  if ($userName -ne $canaryRole -and $userName -ne $poolerUser) {
    throw "VAMO_STAGING_CANARY_APP_DATABASE_URL must use $canaryRole or pooler user $poolerUser, not $userName."
  }

  if ($uri.Host -eq "db.$projectRef.supabase.co") {
    $poolerUserInfo = $uri.UserInfo -replace "^${canaryRole}:", "${poolerUser}:"
    $env:VAMO_STAGING_CANARY_APP_DATABASE_URL = "postgresql://${poolerUserInfo}@${poolerHost}:5432/postgres"
    $uri = [Uri]$env:VAMO_STAGING_CANARY_APP_DATABASE_URL
    Write-Host "Using Supabase session pooler for staging execution: $poolerHost"
  }

  $env:VAMO_STAGING_CANARY_APP_DATABASE_URL = $uri.AbsoluteUri
  Write-Host "Staging DSN user: $(($uri.UserInfo -split ':')[0])"
  Write-Host "Staging DSN host: $($uri.Host)"
}

function Invoke-ControlQuery {
  param(
    [Parameter(Mandatory = $true)][string]$Sql,
    [object[]]$Params = @()
  )

  $payload = @{
    connectionString = $env:INGESTION_CONTROL_DATABASE_URL
    sql = $Sql
    params = $Params
  } | ConvertTo-Json -Compress -Depth 12

  $env:CONFLUENDO_OPERATOR_SQL_PAYLOAD = $payload
  $nodeScript = @'
const { Client } = require("pg");

const payload = JSON.parse(process.env.CONFLUENDO_OPERATOR_SQL_PAYLOAD);
const client = new Client({
  connectionString: payload.connectionString,
  ssl: { rejectUnauthorized: false }
});

(async () => {
  await client.connect();
  const result = await client.query(payload.sql, payload.params);
  console.log(JSON.stringify(result.rows));
  await client.end();
})().catch(async (error) => {
  try { await client.end(); } catch (_) {}
  console.error(error.message);
  process.exit(1);
});
'@

  try {
    $output = $nodeScript | node -
    if ($LASTEXITCODE -ne 0) {
      throw "Control query failed with exit code $LASTEXITCODE."
    }
    if (!$output) {
      return @()
    }
    return @($output | ConvertFrom-Json)
  }
  finally {
    Remove-Item Env:\CONFLUENDO_OPERATOR_SQL_PAYLOAD -ErrorAction SilentlyContinue
  }
}

function Format-TableOrEmpty {
  param([object[]]$Rows)

  if ($Rows.Count -eq 0) {
    Write-Host "(no rows)"
    return
  }

  $Rows | Format-Table -AutoSize | Out-String | Write-Host
}

function Invoke-Step {
  param(
    [Parameter(Mandatory = $true)][string]$Label,
    [Parameter(Mandatory = $true)][scriptblock]$Command
  )

  Write-Host ""
  Write-Host "=== $Label ==="
  & $Command
  $exitCode = $LASTEXITCODE
  if ($null -ne $exitCode -and $exitCode -ne 0) {
    throw "$Label failed with exit code ${exitCode}."
  }
}

function Build-Package {
  if ($NoBuild) {
    Write-Host "Skipping build because -NoBuild was supplied."
    return
  }

  Push-Location $PackageRoot
  try {
    Invoke-Step "Build @confluendo/ingestion-platform" {
      npm run build
    }
  }
  finally {
    Pop-Location
  }
}

function Show-Status {
  $rows = Invoke-ControlQuery -Sql @'
select
  unit_key,
  status,
  run_report ->> 'insertCount' as insert_count,
  run_report ->> 'wroteToTarget' as wrote_to_target,
  blockers
from ingestion_platform.ingestion_batch_queue_items
where unit_key = any($1::text[])
order by run_order;
'@ -Params @(,$UnitKey)

  Write-Host ""
  Write-Host "Queue status"
  Format-TableOrEmpty $rows

  $waves = Invoke-ControlQuery -Sql @'
select
  w.id,
  w.wave_key,
  w.status as wave_status,
  w.summary ->> 'approvalAuditId' as approval_audit_id,
  w.approval_expires_at,
  wi.unit_key,
  wi.status as item_status,
  wi.blockers
from ingestion_platform.ingestion_batch_canary_waves w
join ingestion_platform.ingestion_batch_canary_wave_items wi on wi.wave_id = w.id
where wi.unit_key = any($1::text[])
order by w.id desc
limit 8;
'@ -Params @(,$UnitKey)

  Write-Host "Recent waves"
  Format-TableOrEmpty $waves
}

function Reset-UnitsToDryRunReady {
  $rows = Invoke-ControlQuery -Sql @'
with updated as (
  update ingestion_platform.ingestion_batch_queue_items
  set
    status = 'dry_run_ready',
    run_report = null,
    proposal = null,
    blockers = '[]'::jsonb,
    updated_at = now()
  where unit_key = any($1::text[])
  returning unit_key
)
select
  q.unit_key,
  q.status,
  q.run_report is not null as has_run_report,
  q.blockers
from ingestion_platform.ingestion_batch_queue_items q
where q.unit_key = any($1::text[])
order by q.run_order;
'@ -Params @(,$UnitKey)

  Write-Host ""
  Write-Host "Reset units"
  Format-TableOrEmpty $rows

  if ($rows.Count -ne $UnitKey.Count) {
    throw "Reset matched $($rows.Count) rows, expected $($UnitKey.Count)."
  }
}

function Assert-OnlyRequestedUnitsAreReady {
  $readyRows = Invoke-ControlQuery -Sql @'
select unit_key
from ingestion_platform.ingestion_batch_queue_items
where status = 'dry_run_ready'
  and target_key = 'vamo-place-intelligence'
  and target_environment = 'staging'
order by run_order;
'@

  $ready = @($readyRows | ForEach-Object { $_.unit_key })
  $requested = @($UnitKey)

  $unexpected = @($ready | Where-Object { $_ -notin $requested })
  $missing = @($requested | Where-Object { $_ -notin $ready })

  if ($unexpected.Count -gt 0 -or $missing.Count -gt 0) {
    Write-Host "Current dry_run_ready rows:"
    $ready | ForEach-Object { Write-Host "  - $_" }
    throw "Dry-run ready set does not exactly match requested units. Refusing to run a batch dry-run over unintended units."
  }
}

function Invoke-DryRun {
  $maxUnits = if ($DryRunMaxUnits -gt 0) { $DryRunMaxUnits } else { $UnitKey.Count }
  $timestamp = Get-Date -Format "yyyyMMddHHmmss"
  $auditId = if ($DryRunAuditId) { $DryRunAuditId } else { "operator-$timestamp" }
  $executionKey = if ($DryRunExecutionKey) {
    $DryRunExecutionKey
  } else {
    "batch-dry-run:vamo-eu-poi-sample:operator:$timestamp"
  }

  Push-Location $PackageRoot
  try {
    $previewArgs = @(
      "scripts/run-ip18-batch-dry-run.mjs",
      "--max-units", "$maxUnits",
      "--audit-id", $auditId,
      "--execution-key", $executionKey,
      "--audit-reason", $DryRunAuditReason
    )

    Invoke-Step "Preview IP-18.4 dry-run selection" {
      & node @previewArgs
    }

    $executeArgs = @("scripts/run-ip18-batch-dry-run.mjs", "--execute") + $previewArgs[1..($previewArgs.Count - 1)]

    $env:CONFIRM_CONFLUENDO_BATCH_DRY_RUN = "YES"
    Invoke-Step "Execute IP-18.4 dry-run control update" {
      & node @executeArgs
    }
  }
  finally {
    Remove-Item Env:\CONFIRM_CONFLUENDO_BATCH_DRY_RUN -ErrorAction SilentlyContinue
    Pop-Location
  }
}

function Assert-DryRunReports {
  $rows = Invoke-ControlQuery -Sql @'
select
  unit_key,
  status,
  coalesce((run_report ->> 'insertCount')::int, -1) as insert_count,
  run_report ->> 'wroteToTarget' as wrote_to_target,
  blockers
from ingestion_platform.ingestion_batch_queue_items
where unit_key = any($1::text[])
order by run_order;
'@ -Params @(,$UnitKey)

  Write-Host ""
  Write-Host "Dry-run report verification"
  Format-TableOrEmpty $rows

  foreach ($row in $rows) {
    if ($row.status -ne "dry_run_succeeded") {
      throw "$($row.unit_key) status is $($row.status), expected dry_run_succeeded."
    }
    if ([int]$row.insert_count -ne $ExpectedInsertCount) {
      throw "$($row.unit_key) insert_count is $($row.insert_count), expected $ExpectedInsertCount."
    }
    if ($row.wrote_to_target -ne "false") {
      throw "$($row.unit_key) wrote_to_target is $($row.wrote_to_target), expected false."
    }
  }
}

function Prepare-DryRun {
  if (!$SkipReset) {
    Reset-UnitsToDryRunReady
  } else {
    Write-Host "Skipping reset because -SkipReset was supplied."
  }

  Assert-OnlyRequestedUnitsAreReady
  Build-Package
  Invoke-DryRun
  Assert-DryRunReports

  Write-Host ""
  Write-Host "Prepare complete. Now approve a fresh wave in /admin/ingestion:"
  Write-Host "  Max units: 1"
  Write-Host "  Max rows: $ExpectedInsertCount"
  Write-Host "Then run:"
  Write-Host "  .\scripts\Invoke-Ip18StagingWaveCycle.ps1 -Mode ExecuteWave -ApprovalAuditId <id>"
}

function Execute-Wave {
  $cleanWaveKey = Remove-WrappingQuotes $WaveKey
  $cleanApprovalAuditId = Remove-WrappingQuotes $ApprovalAuditId

  if (!$cleanWaveKey -and !$cleanApprovalAuditId) {
    throw "Pass -ApprovalAuditId <id> or -WaveKey <wave key>."
  }

  Ensure-VamoStagingCanaryAppDsn
  $env:VAMO_STAGING_CANARY_ENVIRONMENT = "staging"
  Build-Package

  Push-Location $PackageRoot
  try {
    $nodeArgs = @(
      "scripts/run-ip18-staging-canary-wave.mjs",
      "--execute"
    )

    if ($cleanWaveKey) {
      $nodeArgs += @("--wave-key", $cleanWaveKey)
    } else {
      $nodeArgs += @("--approval-audit-id", $cleanApprovalAuditId)
    }

    $nodeArgs += @(
      "--max-units", "$WaveMaxUnits",
      "--max-rows", "$WaveMaxRows",
      "--audit-reason", $WaveAuditReason
    )

    $env:CONFIRM_CONFLUENDO_BATCH_STAGING_CANARY = "YES"
    Invoke-Step "Execute IP-18.5 staging-canary wave" {
      & node @nodeArgs
    }
  }
  finally {
    Remove-Item Env:\CONFIRM_CONFLUENDO_BATCH_STAGING_CANARY -ErrorAction SilentlyContinue
    Pop-Location
  }

  Show-Status
}

if ($Mode -eq "Instructions") {
  Show-Instructions
  exit 0
}

Import-OperatorEnv
Assert-ControlDsn

switch ($Mode) {
  "Status" {
    Show-Status
  }
  "PrepareDryRun" {
    Prepare-DryRun
  }
  "ExecuteWave" {
    Execute-Wave
  }
}
