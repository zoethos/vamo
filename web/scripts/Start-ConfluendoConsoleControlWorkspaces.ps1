param(
  [ValidateSet("Staging", "Production")]
  [string]$DefaultEnvironment = "Production",

  [string]$StagingEnvironmentFile,

  [string]$ProductionEnvironmentFile,

  [switch]$Restart,

  [switch]$ClearNextCache,

  [switch]$ValidateOnly
)

$ErrorActionPreference = "Stop"

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$webRoot = (Resolve-Path (Join-Path $scriptDirectory "..")).Path
$consoleRoot = Join-Path $webRoot "apps\confluendo-console"
$consolePort = 4373

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

function Get-ListeningProcessIds {
  param([Parameter(Mandatory = $true)][int]$LocalPort)

  $netstatPath = Join-Path $env:SystemRoot "System32\netstat.exe"
  if (!(Test-Path -LiteralPath $netstatPath -PathType Leaf)) {
    throw "Windows netstat.exe is unavailable; cannot inspect port $LocalPort."
  }

  $listenerPattern = "^\s*TCP\s+\S+:$LocalPort\s+\S+\s+LISTENING\s+(\d+)\s*$"
  $processIds = @()
  foreach ($line in (& $netstatPath -ano -p tcp 2>$null)) {
    if ($line -match $listenerPattern) {
      $processId = [int]$Matches[1]
      if ($processIds -notcontains $processId) {
        $processIds += $processId
      }
    }
  }
  return $processIds
}

function Get-ProcessName {
  param([Parameter(Mandatory = $true)][int]$ProcessId)

  $tasklistPath = Join-Path $env:SystemRoot "System32\tasklist.exe"
  if (!(Test-Path -LiteralPath $tasklistPath -PathType Leaf)) {
    throw "Windows tasklist.exe is unavailable; cannot identify process $ProcessId."
  }

  foreach ($line in (& $tasklistPath /fi "PID eq $ProcessId" /fo csv /nh 2>$null)) {
    if ($line -match '^"([^"]+)","(\d+)"') {
      return $Matches[1]
    }
  }

  return $null
}

function Stop-ProcessTree {
  param([Parameter(Mandatory = $true)][int]$ProcessId)

  $taskkillPath = Join-Path $env:SystemRoot "System32\taskkill.exe"
  if (!(Test-Path -LiteralPath $taskkillPath -PathType Leaf)) {
    throw "Windows taskkill.exe is unavailable; cannot stop process $ProcessId."
  }

  & $taskkillPath /PID $ProcessId /T /F | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "Could not stop process $ProcessId."
  }
}

function Find-ConfluendoConsoleListener {
  param([Parameter(Mandatory = $true)][int]$LocalPort)

  $processIds = @(Get-ListeningProcessIds -LocalPort $LocalPort)
  if ($processIds.Count -eq 0) {
    return $null
  }

  if ($processIds.Count -ne 1) {
    throw "Port $LocalPort has multiple listeners. Stop or inspect them before starting the Confluendo console."
  }

  $processId = [int]$processIds[0]
  $processName = Get-ProcessName -ProcessId $processId
  if ([string]::IsNullOrWhiteSpace($processName)) {
    throw "Port $LocalPort is in use, but its owning process could not be identified."
  }

  # PowerShell 7 on some Windows installations cannot load CimCmdlets, which
  # makes command-line inspection unavailable. Port 4373 is reserved for this
  # console, so an explicit -Restart may replace only its Node listener.
  $isConfluendoConsole =
    $processName -ieq "node.exe"

  return [pscustomobject]@{
    ProcessId = $processId
    ProcessName = $processName
    IsConfluendoConsole = $isConfluendoConsole
  }
}

function Stop-ConfluendoConsoleListener {
  param([Parameter(Mandatory = $true)]$Listener)

  if (!$Listener.IsConfluendoConsole) {
    throw "Port $consolePort is already used by $($Listener.ProcessName) (pid $($Listener.ProcessId)), not this Confluendo console. Refusing to stop it."
  }

  Write-Host "Stopping the existing Confluendo console listener (pid $($Listener.ProcessId))."
  Stop-ProcessTree -ProcessId $Listener.ProcessId

  for ($attempt = 1; $attempt -le 10; $attempt++) {
    Start-Sleep -Milliseconds 300
    $currentListener = Find-ConfluendoConsoleListener -LocalPort $consolePort
    if ($null -eq $currentListener) {
      return
    }
  }

  throw "The existing Confluendo console listener did not stop. Check port $consolePort before retrying."
}

function Clear-ConfluendoConsoleNextCache {
  $nextCache = Join-Path $consoleRoot ".next"
  if (!(Test-Path -LiteralPath $nextCache)) {
    Write-Host "Next.js cache already absent: $nextCache"
    return
  }

  Write-Host "Removing Confluendo console Next.js cache: $nextCache"
  Remove-Item -LiteralPath $nextCache -Recurse -Force
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

  $existingListener = Find-ConfluendoConsoleListener -LocalPort $consolePort
  if ($existingListener) {
    if (!$existingListener.IsConfluendoConsole) {
      throw "Port $consolePort is already used by $($existingListener.ProcessName) (pid $($existingListener.ProcessId)), not this Confluendo console. Refusing to replace it."
    }

    if (!$Restart) {
      Write-Host "Confluendo console is already running at http://localhost:$consolePort/admin/ingestion (pid $($existingListener.ProcessId))."
      Write-Host "It keeps its current workspace profile. Run this script again with -Restart to apply $DefaultEnvironment as the default workspace."
      if ($ClearNextCache) {
        Write-Host "Cache was not cleared because the active console was not restarted. Add -Restart to clear it safely."
      }
      return
    }

    Stop-ConfluendoConsoleListener -Listener $existingListener
  }

  if ($ClearNextCache) {
    Clear-ConfluendoConsoleNextCache
  }

  Write-Host ""
  Write-Host "Starting Confluendo console with switchable control workspaces"
  Write-Host "Default workspace: $DefaultEnvironment"
  Write-Host "Console: http://localhost:$consolePort/admin/ingestion"
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
