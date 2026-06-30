param(
  [int]$Port = 4373,
  [switch]$NoCacheReset
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$WebRoot = Join-Path $RepoRoot "web"
$SiteRoot = Join-Path $WebRoot "apps\site"
$NextCache = Join-Path $SiteRoot ".next"
$LogPath = Join-Path $env:TEMP "vamo-web-dashboard-$Port.log"

function Get-PortProcessIds {
  param([int]$TargetPort)

  Get-NetTCPConnection -LocalPort $TargetPort -ErrorAction SilentlyContinue |
    Where-Object { $_.State -eq "Listen" -and $_.OwningProcess -gt 0 } |
    Select-Object -ExpandProperty OwningProcess -Unique
}

function Wait-PortReleased {
  param(
    [int]$TargetPort,
    [int]$TimeoutSeconds = 15
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    if (-not (Get-PortProcessIds -TargetPort $TargetPort)) {
      return
    }
    Start-Sleep -Milliseconds 300
  }

  throw "Port $TargetPort is still in use after waiting $TimeoutSeconds seconds."
}

if (-not (Test-Path -LiteralPath $WebRoot)) {
  throw "Cannot find web workspace at $WebRoot"
}

$runningPids = @(Get-PortProcessIds -TargetPort $Port)
if ($runningPids.Count -gt 0) {
  Write-Host "Dashboard is already listening on port $Port. Resetting process(es): $($runningPids -join ', ')"
  foreach ($processId in $runningPids) {
    Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
  }
  Wait-PortReleased -TargetPort $Port

  if (-not $NoCacheReset -and (Test-Path -LiteralPath $NextCache)) {
    $resolvedCache = (Resolve-Path -LiteralPath $NextCache).Path
    $expectedCache = (Join-Path (Resolve-Path -LiteralPath $SiteRoot).Path ".next")
    if ($resolvedCache -ne $expectedCache) {
      throw "Refusing to delete unexpected cache path: $resolvedCache"
    }
    Write-Host "Removing Next.js cache: $resolvedCache"
    Remove-Item -LiteralPath $resolvedCache -Recurse -Force
  }
} else {
  Write-Host "Dashboard is not listening on port $Port. Starting it."
}

Remove-Item -LiteralPath $LogPath -Force -ErrorAction SilentlyContinue

$command = @"
cd "$WebRoot"
npm --workspace @vamo/site run dev *> "$LogPath"
"@

Start-Process -FilePath "powershell" `
  -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $command `
  -WindowStyle Hidden

Start-Sleep -Seconds 5

$listenerPids = @(Get-PortProcessIds -TargetPort $Port)
if ($listenerPids.Count -eq 0) {
  Write-Host "Dashboard did not start listening on port $Port yet."
  Write-Host "Log: $LogPath"
  if (Test-Path -LiteralPath $LogPath) {
    Get-Content -LiteralPath $LogPath -Tail 80
  }
  exit 1
}

Write-Host "Dashboard is running at http://localhost:$Port"
Write-Host "Process id(s): $($listenerPids -join ', ')"
Write-Host "Log: $LogPath"
