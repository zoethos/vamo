# Runs the app on the first connected Android device, no id memorizing.
$ErrorActionPreference = 'Stop'
$devices = flutter devices --machine | ConvertFrom-Json
$android = $devices | Where-Object { $_.targetPlatform -like 'android*' } | Select-Object -First 1
if (-not $android) {
  Write-Host 'No Android device connected (check USB debugging / Auto Blocker).' -ForegroundColor Yellow
  exit 1
}
Write-Host "Running on $($android.name) ($($android.id))" -ForegroundColor Cyan
Set-Location (Join-Path $PSScriptRoot '..\app')
flutter run -d $android.id
exit $LASTEXITCODE
