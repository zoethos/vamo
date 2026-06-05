# Local runner for tool/rls_smoke.dart against the cloud project.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\tool\rls-smoke.local.ps1
#
# Notes:
# - Keep this file local-only if you prefer (add to .gitignore) since it contains credentials.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Set-Location 'Z:\vamo'

$env:SUPABASE_URL = 'https://mjercplkmuoctdklosyy.supabase.co'
$env:SUPABASE_ANON_KEY = 'sb_publishable__4epI8UNhNDyw47y_sZEIQ_99vCOsQR'

$env:RLS_USER_A_EMAIL = 'rls-a@test.local'
$env:RLS_USER_A_PASSWORD = 'the-password'

$env:RLS_USER_B_EMAIL = 'rls-b@test.local'
$env:RLS_USER_B_PASSWORD = 'the-password'

$env:RLS_USER_C_EMAIL = 'rls-c@test.local'
$env:RLS_USER_C_PASSWORD = 'the-password'

dart run tool/rls_smoke.dart
