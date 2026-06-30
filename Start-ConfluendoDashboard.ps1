param(
    [int]$Port = 4373,
    [switch]$NoCacheReset,
    [switch]$ForceCacheReset
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$WebRoot = Join-Path $Root "web"
$SiteRoot = Join-Path $WebRoot "apps\site"
$NextCache = Join-Path $SiteRoot ".next"
$SiteTurboCache = Join-Path $SiteRoot ".turbo"
$DevStatePath = Join-Path $SiteRoot ".confluendo-dev-state.json"
$OutLog = Join-Path $env:TEMP "confluendo-dashboard-$Port.log"
$ErrLog = Join-Path $env:TEMP "confluendo-dashboard-$Port.err.log"
$DevStateVersion = 1

$BuildStateInputs = @(
    "web\package-lock.json",
    "web\package.json",
    "web\turbo.json",
    "web\apps\site\package.json",
    "web\apps\site\next.config.ts",
    "web\apps\site\tsconfig.json",
    "web\packages\ingestion-platform\package.json",
    "web\packages\ingestion-platform\tsconfig.json"
)

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
    param(
        [object]$CurrentState
    )

    $decision = Get-CacheDecision -CurrentState $CurrentState

    if (-not $decision.ShouldClear) {
        Write-Host ("Keeping Next.js cache: {0}" -f $decision.Reason)
        Write-DevState -State $CurrentState
        return
    }

    Write-Host ("Clearing Next.js cache: {0}" -f $decision.Reason)
    Remove-SiteChildPath -Path $NextCache -Label ".next"
    Remove-SiteChildPath -Path $SiteTurboCache -Label ".turbo"
    Write-DevState -State $CurrentState
}

function Get-CacheDecision {
    param([object]$CurrentState)

    if ($NoCacheReset) {
        return [pscustomobject]@{
            ShouldClear = $false
            Reason = "-NoCacheReset was supplied"
        }
    }

    if ($ForceCacheReset) {
        return [pscustomobject]@{
            ShouldClear = $true
            Reason = "-ForceCacheReset was supplied"
        }
    }

    if (-not (Test-Path -LiteralPath $NextCache)) {
        return [pscustomobject]@{
            ShouldClear = $false
            Reason = "no .next cache found"
        }
    }

    if (-not (Test-Path -LiteralPath $DevStatePath)) {
        return [pscustomobject]@{
            ShouldClear = $true
            Reason = "dev-state marker is missing"
        }
    }

    try {
        $previousState = Get-Content -LiteralPath $DevStatePath -Raw | ConvertFrom-Json
    }
    catch {
        return [pscustomobject]@{
            ShouldClear = $true
            Reason = "dev-state marker could not be read"
        }
    }

    $changes = [System.Collections.Generic.List[string]]::new()
    if ($previousState.stateVersion -ne $CurrentState.stateVersion) {
        $changes.Add("state version changed")
    }
    if ($previousState.branch -ne $CurrentState.branch) {
        $changes.Add(("branch changed {0} -> {1}" -f $previousState.branch, $CurrentState.branch))
    }
    if ($previousState.head -ne $CurrentState.head) {
        $changes.Add(("HEAD changed {0} -> {1}" -f $previousState.head, $CurrentState.head))
    }
    if ($previousState.buildInputHash -ne $CurrentState.buildInputHash) {
        $changes.Add("build inputs changed")
    }

    if ($changes.Count -gt 0) {
        return [pscustomobject]@{
            ShouldClear = $true
            Reason = ($changes -join "; ")
        }
    }

    return [pscustomobject]@{
        ShouldClear = $false
        Reason = ("branch {0}, HEAD {1}, build inputs unchanged" -f $CurrentState.branch, $CurrentState.head)
    }
}

function Remove-SiteChildPath {
    param(
        [string]$Path,
        [string]$Label
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Host ("No {0} cache found." -f $Label)
        return
    }

    $resolvedSite = (Resolve-Path -LiteralPath $SiteRoot).Path
    $resolvedPath = (Resolve-Path -LiteralPath $Path).Path

    if (-not $resolvedPath.StartsWith($resolvedSite, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove unexpected cache path: $resolvedPath"
    }

    Write-Host ("Removing {0}: {1}" -f $Label, $resolvedPath)
    Remove-Item -LiteralPath $resolvedPath -Recurse -Force
}

function Get-DevState {
    $branch = (& git -C $Root branch --show-current 2>$null)
    if ($LASTEXITCODE -ne 0 -or -not $branch) {
        $branch = "unknown"
    }

    $head = (& git -C $Root rev-parse --short=12 --verify HEAD 2>$null)
    if ($LASTEXITCODE -ne 0 -or -not $head) {
        $head = "unknown"
    }

    return [pscustomobject]@{
        stateVersion = $DevStateVersion
        branch = ($branch | Select-Object -First 1).Trim()
        head = ($head | Select-Object -First 1).Trim()
        buildInputHash = Get-BuildInputHash
        inputs = $BuildStateInputs
    }
}

function Get-BuildInputHash {
    $segments = foreach ($relativePath in $BuildStateInputs) {
        $absolutePath = Join-Path $Root $relativePath
        if (Test-Path -LiteralPath $absolutePath) {
            $hash = Get-FileSha256 -Path $absolutePath
            "{0}={1}" -f $relativePath, $hash
        }
        else {
            "{0}=missing" -f $relativePath
        }
    }

    return Get-StringSha256 -Value ($segments -join "`n")
}

function Get-FileSha256 {
    param([string]$Path)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $hashBytes = $sha.ComputeHash($stream)
        return [System.BitConverter]::ToString($hashBytes).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $stream.Dispose()
        $sha.Dispose()
    }
}

function Get-StringSha256 {
    param([string]$Value)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
        $hashBytes = $sha.ComputeHash($bytes)
        return [System.BitConverter]::ToString($hashBytes).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Write-DevState {
    param([object]$State)

    $State | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $DevStatePath -Encoding UTF8
    Write-Host ("Dev-state marker: {0}" -f $DevStatePath)
}

if (-not (Test-Path -LiteralPath (Join-Path $WebRoot "package.json"))) {
    throw "Cannot find web/package.json under $Root. Run this script from the vamo-web-dashboard checkout."
}

$currentState = Get-DevState

Stop-PortOwner -TargetPort $Port
Clear-NextCache -CurrentState $currentState

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
