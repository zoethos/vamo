<#
Sends a signed synthetic Supabase Auth email hook to send-auth-email.

Use this against staging after RESEND_API_KEY is set and Brevo has been made to
fail intentionally on that staging project. Unless -DryRun is passed, the
script sends a real email to the supplied address.
#>
[CmdletBinding()]
param(
  [string]$SupabaseUrl = $env:SUPABASE_URL,
  [string]$HookSecret = $env:SEND_EMAIL_HOOK_SECRET,
  [string]$To = $env:TEST_AUTH_EMAIL_TO,
  [string]$Action = "magiclink",
  [string]$RedirectTo = "app.vamo://auth/callback",
  [string]$Token = "123456",
  [string]$TokenHash = "fallback-proof-token-hash",
  [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$knownProdSupabaseRef = "mjercplkmuoctdklosyy"

if (-not $SupabaseUrl) {
  throw "Set SUPABASE_URL or pass -SupabaseUrl."
}
if (-not $HookSecret) {
  throw "Set SEND_EMAIL_HOOK_SECRET or pass -HookSecret."
}
if (-not $To) {
  throw "Set TEST_AUTH_EMAIL_TO or pass -To."
}
if ($SupabaseUrl.Contains($knownProdSupabaseRef)) {
  throw "Refusing to invoke the known production project ref. Use staging for email fallback proof."
}

function ConvertFrom-Base64Url {
  param([Parameter(Mandatory = $true)][string]$Value)

  $normalized = $Value.Replace("-", "+").Replace("_", "/")
  switch ($normalized.Length % 4) {
    0 { }
    2 { $normalized += "==" }
    3 { $normalized += "=" }
    default { throw "Invalid base64url secret length." }
  }
  return [Convert]::FromBase64String($normalized)
}

$secretValue = $HookSecret.Trim()
if ($secretValue.StartsWith("v1,whsec_")) {
  $secretValue = $secretValue.Substring("v1,whsec_".Length)
} elseif ($secretValue.StartsWith("whsec_")) {
  $secretValue = $secretValue.Substring("whsec_".Length)
}

$payloadObject = [ordered]@{
  user = [ordered]@{
    email = $To
  }
  email_data = [ordered]@{
    token = $Token
    token_hash = $TokenHash
    redirect_to = $RedirectTo
    email_action_type = $Action
    site_url = $SupabaseUrl.TrimEnd("/")
  }
}

$payload = $payloadObject | ConvertTo-Json -Depth 8 -Compress
$webhookId = "msg_" + [Guid]::NewGuid().ToString("N")
$timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$signedContent = "$webhookId.$timestamp.$payload"
$secretBytes = ConvertFrom-Base64Url $secretValue
$hmac = [System.Security.Cryptography.HMACSHA256]::new($secretBytes)
$signatureBytes = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($signedContent))
$signature = "v1," + [Convert]::ToBase64String($signatureBytes)

$functionUrl = $SupabaseUrl.TrimEnd("/") + "/functions/v1/send-auth-email"
$headers = @{
  "webhook-id" = $webhookId
  "webhook-timestamp" = [string]$timestamp
  "webhook-signature" = $signature
}

Write-Host "Invoking send-auth-email at $functionUrl"
Write-Host "Recipient: $To"
if ($DryRun) {
  Write-Host "Dry run only. Signed payload and headers were built, but no request was sent."
  Write-Host "Webhook id: $webhookId"
  Write-Host "Payload bytes: $([System.Text.Encoding]::UTF8.GetByteCount($payload))"
  exit 0
}

$response = Invoke-WebRequest `
  -Uri $functionUrl `
  -Method Post `
  -Headers $headers `
  -ContentType "application/json" `
  -Body $payload

Write-Host "HTTP status: $($response.StatusCode)"
Write-Host "Response body: $($response.Content)"
Write-Host "Proof step: confirm the email arrived, then inspect Supabase Edge Function logs for 'Auth email sent via fallback provider' with provider=resend."
