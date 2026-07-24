param(
  [int]$Port = 4373,
  [switch]$Restart,
  [switch]$SkipPortStop,
  [switch]$ClearTurboCache
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$WebRoot = (Resolve-Path (Join-Path $ScriptDir "..")).Path
$ConsoleRoot = Join-Path $WebRoot "apps\confluendo-console"
$PidFile = Join-Path $WebRoot ".confluendo-console-dev.pid"

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

function Stop-PortListeners {
  param([Parameter(Mandatory = $true)][int]$LocalPort)

  $processIds = @(Get-ListeningProcessIds -LocalPort $LocalPort | Where-Object { $_ -and $_ -ne $PID })

  if ($processIds.Count -eq 0) {
    Write-Host "No listener found on port $LocalPort."
    return
  }

  foreach ($processId in $processIds) {
    $processName = Get-ProcessName -ProcessId $processId
    if ([string]::IsNullOrWhiteSpace($processName)) {
      continue
    }

    Write-Host "Stopping port $LocalPort listener: $processName (pid $processId)"
    Stop-ProcessTree -ProcessId $processId
  }
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

function Stop-TrackedConsoleDevServer {
  if (!(Test-Path -LiteralPath $PidFile)) {
    return
  }

  $trackedPidRaw = (Get-Content -LiteralPath $PidFile -ErrorAction SilentlyContinue | Select-Object -First 1)
  $trackedPid = 0
  if ([int]::TryParse($trackedPidRaw, [ref]$trackedPid) -and $trackedPid -gt 0 -and $trackedPid -ne $PID) {
    $processName = Get-ProcessName -ProcessId $trackedPid
    if (![string]::IsNullOrWhiteSpace($processName)) {
      Write-Host "Stopping tracked console dev wrapper: $processName (pid $trackedPid)"
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

if (!(Test-Path -LiteralPath $ConsoleRoot)) {
  throw "Missing Confluendo console app directory: $ConsoleRoot"
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
  Start-ConsoleDevServer -LocalPort $Port
} else {
  Write-Host ""
  Write-Host "Cache cleared. Restart with:"
  Write-Host "  npm --workspace @confluendo/console run dev"
  Write-Host ""
  Write-Host "Or run this script with -Restart."
}
