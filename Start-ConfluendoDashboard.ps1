param(
    [int]$Port = 4373,
    [switch]$NoCacheReset
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$WebRoot = Join-Path $Root "web"
$SiteRoot = Join-Path $WebRoot "apps\site"
$NextCache = Join-Path $SiteRoot ".next"
$OutLog = Join-Path $env:TEMP "confluendo-dashboard-$Port.log"
$ErrLog = Join-Path $env:TEMP "confluendo-dashboard-$Port.err.log"

function Stop-PortOwner {
    param([int]$TargetPort)

    $connections = Get-NetTCPConnection -LocalPort $TargetPort -State Listen -ErrorAction SilentlyContinue
    $processIds = $connections | Select-Object -ExpandProperty OwningProcess -Unique

    if (-not $processIds) {
        Write-Host "No listener found on port $TargetPort."
        return
    }

    foreach ($processId in $processIds) {
        try {
            $process = Get-Process -Id $processId -ErrorAction Stop
            Write-Host ("Stopping process on port {0}: {1} (PID {2})" -f $TargetPort, $process.ProcessName, $processId)
            Stop-Process -Id $processId -Force
        }
        catch {
            Write-Warning ("Could not stop PID {0}: {1}" -f $processId, $_.Exception.Message)
        }
    }

    Start-Sleep -Milliseconds 750
}

function Clear-NextCache {
    if ($NoCacheReset) {
        Write-Host "Skipping .next reset because -NoCacheReset was supplied."
        return
    }

    if (-not (Test-Path -LiteralPath $NextCache)) {
        Write-Host "No .next cache found."
        return
    }

    $resolvedSite = (Resolve-Path -LiteralPath $SiteRoot).Path
    $resolvedCache = (Resolve-Path -LiteralPath $NextCache).Path

    if (-not $resolvedCache.StartsWith($resolvedSite, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove unexpected cache path: $resolvedCache"
    }

    Write-Host "Removing stale Next.js cache: $resolvedCache"
    Remove-Item -LiteralPath $resolvedCache -Recurse -Force
}

if (-not (Test-Path -LiteralPath (Join-Path $WebRoot "package.json"))) {
    throw "Cannot find web/package.json under $Root. Run this script from the vamo-web-dashboard checkout."
}

Stop-PortOwner -TargetPort $Port
Clear-NextCache

Write-Host "Starting Confluendo dashboard on http://localhost:$Port/admin/ingestion"
Write-Host "stdout: $OutLog"
Write-Host "stderr: $ErrLog"

$process = Start-Process `
    -FilePath "npm.cmd" `
    -ArgumentList @("--workspace", "@vamo/site", "run", "dev") `
    -WorkingDirectory $WebRoot `
    -RedirectStandardOutput $OutLog `
    -RedirectStandardError $ErrLog `
    -WindowStyle Hidden `
    -PassThru

Start-Sleep -Seconds 3

if ($process.HasExited) {
    Write-Error "Dashboard process exited early with code $($process.ExitCode). Check $ErrLog"
}

Write-Host "Dashboard process started (PID $($process.Id))."
Write-Host "Open: http://localhost:$Port/admin/ingestion"
