param(
  [string]$Port = "4373",
  [switch]$Restart,
  [switch]$SkipPortStop,
  [switch]$ClearTurboCache,
  [ValidateSet("Staging", "Production")]
  [string]$DefaultControlEnvironment = "Staging",
  [switch]$UseLegacyConsoleEnvironment,
  [Alias("h", "help")]
  [switch]$ShowHelp,
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$RemainingArguments
)

$ErrorActionPreference = "Stop"

function Show-ResetConfluendoConsoleNextCacheHelp {
  @"
Reset-ConfluendoConsoleNextCache.ps1

Clears generated Next.js cache output for the Confluendo console. When both
.env.staging.local and .env.production.local are present, -Restart starts the
switchable control-workspace console and defaults to Staging.

Usage:
  .\scripts\Reset-ConfluendoConsoleNextCache.ps1 [options]

Options:
  -Restart
      Restart the console after clearing cache.
  -ClearTurboCache
      Also remove local Turbo caches.
  -DefaultControlEnvironment Staging|Production
      Default workspace after a profile-aware restart. Default: Staging.
  -UseLegacyConsoleEnvironment
      Use the single-profile .env.local restart path instead of switchable
      Staging/Production profiles. Required for a custom port.
  -Port <number>
      Console port. Default: 4373. Profile-aware restart supports 4373 only.
  -SkipPortStop
      Do not stop the current listener before clearing cache.

Examples:
  # Clear cache and restart with Staging selected.
  .\scripts\Reset-ConfluendoConsoleNextCache.ps1 -Restart

  # Clear Next.js and Turbo caches, then restart with Production selected.
  .\scripts\Reset-ConfluendoConsoleNextCache.ps1 -Restart -ClearTurboCache -DefaultControlEnvironment Production

  # Use a legacy, single-profile setup on another port.
  .\scripts\Reset-ConfluendoConsoleNextCache.ps1 -Restart -UseLegacyConsoleEnvironment -Port 4374

Help aliases: -h, -help, --help, /h, /?
"@ | Write-Output
}

$helpAliases = @("-h", "-help", "--help", "/h", "/?")
$rawArguments = @($Port) + @($RemainingArguments)
if ($ShowHelp -or @($rawArguments | Where-Object { $_ -in $helpAliases }).Count -gt 0) {
  Show-ResetConfluendoConsoleNextCacheHelp
  exit 0
}
if ($RemainingArguments.Count -gt 0) {
  throw "Unknown option(s): $($RemainingArguments -join ', '). Run with -h for usage."
}
if ($Port -match "^(?:-|/)") {
  throw "Unknown option: $Port. Run with -h for usage."
}
try {
  $Port = [int]$Port
} catch {
  throw "Port must be an integer. Run with -h for usage."
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$WebRoot = (Resolve-Path (Join-Path $ScriptDir "..")).Path
$ConsoleRoot = Join-Path $WebRoot "apps\confluendo-console"
$PidFile = Join-Path $WebRoot ".confluendo-console-dev.pid"
$ControlWorkspaceLauncher = Join-Path $ScriptDir "Start-ConfluendoConsoleControlWorkspaces.ps1"
$StagingEnvironmentFile = Join-Path $WebRoot ".env.staging.local"
$ProductionEnvironmentFile = Join-Path $WebRoot ".env.production.local"

function Assert-PathInside {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Root
  )

  $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd("\")
  $pathFull = [System.IO.Path]::GetFullPath($Path).TrimEnd("\")

  if ($pathFull -ne $rootFull -and !$pathFull.StartsWith("$rootFull\", [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to operate outside expected root. Path: $pathFull Root: $rootFull"
  }
}

function Remove-DirectoryIfPresent {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Root
  )

  Assert-PathInside -Path $Path -Root $Root

  if (Test-Path -LiteralPath $Path) {
    Write-Host "Removing: $Path"
    Remove-Item -LiteralPath $Path -Recurse -Force
  } else {
    Write-Host "Already absent: $Path"
  }
}

function Stop-PortListeners {
  param([Parameter(Mandatory = $true)][int]$LocalPort)

  $connections = Get-NetTCPConnection -LocalPort $LocalPort -State Listen -ErrorAction SilentlyContinue
  $processIds = @($connections | Select-Object -ExpandProperty OwningProcess -Unique | Where-Object { $_ -and $_ -ne $PID })

  if ($processIds.Count -eq 0) {
    Write-Host "No listener found on port $LocalPort."
    return
  }

  foreach ($processId in $processIds) {
    $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
    if (!$process) {
      continue
    }

    Write-Host "Stopping port $LocalPort listener: $($process.ProcessName) (pid $processId)"
    Stop-ProcessTree -ProcessId $processId
  }
}

function Stop-ProcessTree {
  param([Parameter(Mandatory = $true)][int]$ProcessId)

  $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$ProcessId" -ErrorAction SilentlyContinue)
  foreach ($child in $children) {
    Stop-ProcessTree -ProcessId ([int]$child.ProcessId)
  }

  $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
  if ($process) {
    Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
  }
}

function Stop-TrackedConsoleDevServer {
  if (!(Test-Path -LiteralPath $PidFile)) {
    return
  }

  $trackedPidRaw = (Get-Content -LiteralPath $PidFile -ErrorAction SilentlyContinue | Select-Object -First 1)
  $trackedPid = 0
  if ([int]::TryParse($trackedPidRaw, [ref]$trackedPid) -and $trackedPid -gt 0 -and $trackedPid -ne $PID) {
    $process = Get-Process -Id $trackedPid -ErrorAction SilentlyContinue
    if ($process) {
      Write-Host "Stopping tracked console dev wrapper: $($process.ProcessName) (pid $trackedPid)"
      Stop-ProcessTree -ProcessId $trackedPid
    }
  }

  Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
}

function Escape-SingleQuotedPowerShell {
  param([Parameter(Mandatory = $true)][string]$Value)
  return $Value.Replace("'", "''")
}

function Start-ConsoleDevServer {
  param([Parameter(Mandatory = $true)][int]$LocalPort)

  $stdoutLog = Join-Path $WebRoot "console-dev-$LocalPort.log"
  $stderrLog = Join-Path $WebRoot "console-dev-$LocalPort.err.log"
  $webRootLiteral = Escape-SingleQuotedPowerShell $WebRoot
  $stdoutLiteral = Escape-SingleQuotedPowerShell $stdoutLog
  $stderrLiteral = Escape-SingleQuotedPowerShell $stderrLog

  Remove-Item -LiteralPath $stdoutLog, $stderrLog -Force -ErrorAction SilentlyContinue

  $command = @"
Set-Location -LiteralPath '$webRootLiteral'
npm --workspace @confluendo/console run dev 1>> '$stdoutLiteral' 2>> '$stderrLiteral'
"@

  $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
  $process = Start-Process -FilePath "powershell.exe" `
    -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-EncodedCommand", $encodedCommand) `
    -WindowStyle Hidden `
    -PassThru

  Set-Content -LiteralPath $PidFile -Value $process.Id -Encoding ascii

  Write-Host "Started console dev server process pid $($process.Id)."
  Write-Host "pid file: $PidFile"
  Write-Host "stdout: $stdoutLog"
  Write-Host "stderr: $stderrLog"

  $url = "http://localhost:$LocalPort/admin/ingestion"
  for ($attempt = 1; $attempt -le 30; $attempt++) {
    Start-Sleep -Seconds 1
    try {
      $response = Invoke-WebRequest -Uri $url -MaximumRedirection 0 -ErrorAction Stop
      if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 400) {
        Write-Host "Console responded at $url"
        return
      }
    } catch {
      $statusCode = $_.Exception.Response.StatusCode.value__
      if ($statusCode -ge 300 -and $statusCode -lt 400) {
        Write-Host "Console responded at $url with redirect status $statusCode"
        return
      }
    }
  }

  Write-Warning "Console did not respond within 30 seconds. Check $stderrLog"
}

function Start-ControlWorkspaceConsoleDevServer {
  param([Parameter(Mandatory = $true)][int]$LocalPort)

  if ($LocalPort -ne 4373) {
    throw "Control-workspace restart supports port 4373 only. Use -UseLegacyConsoleEnvironment for a custom port."
  }
  if (!(Test-Path -LiteralPath $ControlWorkspaceLauncher -PathType Leaf)) {
    throw "Missing control-workspace launcher: $ControlWorkspaceLauncher"
  }

  $stdoutLog = Join-Path $WebRoot "console-workspaces-$LocalPort.log"
  $stderrLog = Join-Path $WebRoot "console-workspaces-$LocalPort.err.log"
  Remove-Item -LiteralPath $stdoutLog, $stderrLog -Force -ErrorAction SilentlyContinue

  $process = Start-Process -FilePath "powershell.exe" `
    -ArgumentList @(
      "-NoProfile",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      $ControlWorkspaceLauncher,
      "-DefaultEnvironment",
      $DefaultControlEnvironment,
      "-StagingEnvironmentFile",
      $StagingEnvironmentFile,
      "-ProductionEnvironmentFile",
      $ProductionEnvironmentFile
    ) `
    -WorkingDirectory $WebRoot `
    -RedirectStandardOutput $stdoutLog `
    -RedirectStandardError $stderrLog `
    -WindowStyle Hidden `
    -PassThru

  Set-Content -LiteralPath $PidFile -Value $process.Id -Encoding ascii

  Write-Host "Started switchable control-workspace console process pid $($process.Id)."
  Write-Host "Default workspace: $DefaultControlEnvironment"
  Write-Host "stdout: $stdoutLog"
  Write-Host "stderr: $stderrLog"

  $url = "http://localhost:$LocalPort/admin/ingestion"
  for ($attempt = 1; $attempt -le 30; $attempt++) {
    Start-Sleep -Seconds 1
    try {
      $response = Invoke-WebRequest -Uri $url -MaximumRedirection 0 -ErrorAction Stop
      if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 400) {
        Write-Host "Console responded at $url"
        return
      }
    } catch {
      $statusCode = $_.Exception.Response.StatusCode.value__
      if ($statusCode -ge 300 -and $statusCode -lt 400) {
        Write-Host "Console responded at $url with redirect status $statusCode"
        return
      }
    }
  }

  Write-Warning "Console did not respond within 30 seconds. Check $stderrLog"
}

if (!(Test-Path -LiteralPath $ConsoleRoot)) {
  throw "Missing Confluendo console app directory: $ConsoleRoot"
}

$hasControlWorkspaceProfiles =
  (Test-Path -LiteralPath $StagingEnvironmentFile -PathType Leaf) -and
  (Test-Path -LiteralPath $ProductionEnvironmentFile -PathType Leaf)
$shouldUseControlWorkspaces = $Restart -and !$UseLegacyConsoleEnvironment -and $hasControlWorkspaceProfiles

if ($shouldUseControlWorkspaces -and $Port -ne 4373) {
  throw "Control-workspace restart supports port 4373 only. Use -UseLegacyConsoleEnvironment for a custom port."
}

if ($shouldUseControlWorkspaces) {
  # Validate profiles before stopping a working console or clearing its cache.
  & $ControlWorkspaceLauncher `
    -DefaultEnvironment $DefaultControlEnvironment `
    -StagingEnvironmentFile $StagingEnvironmentFile `
    -ProductionEnvironmentFile $ProductionEnvironmentFile `
    -ValidateOnly
}

Write-Host "Confluendo console Next.js cache reset"
Write-Host "Web root: $WebRoot"
Write-Host "Console app: $ConsoleRoot"
Write-Host "Port: $Port"
Write-Host ""

if (!$SkipPortStop) {
  Stop-TrackedConsoleDevServer
  Stop-PortListeners -LocalPort $Port
  Start-Sleep -Seconds 1
} else {
  Write-Host "Skipping port stop."
}

Remove-DirectoryIfPresent -Path (Join-Path $ConsoleRoot ".next") -Root $ConsoleRoot

if ($ClearTurboCache) {
  Remove-DirectoryIfPresent -Path (Join-Path $WebRoot ".turbo") -Root $WebRoot
  Remove-DirectoryIfPresent -Path (Join-Path $WebRoot "node_modules\.cache\turbo") -Root $WebRoot
}

if ($Restart) {
  if ($shouldUseControlWorkspaces) {
    Start-ControlWorkspaceConsoleDevServer -LocalPort $Port
  } else {
    Start-ConsoleDevServer -LocalPort $Port
  }
} else {
  Write-Host ""
  Write-Host "Cache cleared. Restart with:"
  if ($hasControlWorkspaceProfiles -and !$UseLegacyConsoleEnvironment) {
    Write-Host "  .\scripts\Reset-ConfluendoConsoleNextCache.ps1 -Restart -DefaultControlEnvironment $DefaultControlEnvironment"
  } else {
    Write-Host "  npm --workspace @confluendo/console run dev"
  }
  Write-Host ""
  Write-Host "Or run this script with -Restart."
}
