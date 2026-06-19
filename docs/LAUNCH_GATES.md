# Cycle 2 Launch Gates

This is the public-v1 eligibility checklist. Code for the feature batch can be
merged while these are open, but closed beta should not widen until every gate
below is green.

## Gate 1 - Email SPOF Closed

Owner: ops + agent proof script.

Status needed:

- Resend sender domain verified.
- `RESEND_API_KEY` set in Supabase.
- `RESEND_SENDER_EMAIL` set if it differs from `SENDER_EMAIL`.
- Forced-fallback proof passes on staging.

Commands:

```powershell
supabase secrets set `
  RESEND_API_KEY="<resend-key>" `
  RESEND_SENDER_EMAIL="noreply@vamo.world" `
  --project-ref <staging-ref>
```

For the forced fallback, temporarily make Brevo fail on staging only, invoke the
signed hook, then restore the real Brevo key:

```powershell
supabase secrets set BREVO_API_KEY="invalid-for-fallback-proof" --project-ref <staging-ref>

$env:SUPABASE_URL = "https://<staging-ref>.supabase.co"
$env:SEND_EMAIL_HOOK_SECRET = "<staging-hook-secret>"
$env:TEST_AUTH_EMAIL_TO = "<your-test-email>"
.\tool\email_fallback_proof.ps1 -DryRun
.\tool\email_fallback_proof.ps1

supabase secrets set BREVO_API_KEY="<real-staging-brevo-key>" --project-ref <staging-ref>
```

Pass criteria:

- the proof email arrives
- `send-auth-email` logs `Auth email sent via fallback provider` with
  `provider=resend`
- Brevo key is restored after the proof

## Gate 2 - Crashlytics Proof

Owner: device QA.

Status needed:

- Android tester build installed from Firebase App Distribution.
- One deliberate forced crash appears in Firebase Crashlytics for that exact
  app version/build number.
- Debug/local crashes do not pollute the dashboard.

Pass criteria:

- Crashlytics shows the event under the tester build version
- no unexpected fatal events appear during scenario/k6 validation

## Gate 3 - App Links SHA

Owner: ops for Play SHA, agent for `assetlinks.json` patch, ops for redeploy.

Steps:

1. In Play Console, copy the Play App Signing certificate SHA-256.
2. Patch `web/apps/site/public/.well-known/assetlinks.json`.
3. Redeploy the site.
4. Install the Firebase tester build and open an invite/QR link.

Pass criteria:

- Android opens the installed app from the invite link
- the browser fallback still works when the app is absent

## Gate 4 - DR Basics

Owner: ops + agent scripts.

Status needed:

- Supabase Pro enabled.
- PITR enabled.
- `supabase backups list --project-ref <prod-ref>` shows recent backups.
- Logical export generated and uploaded off-site.
- Restore drill replayed into disposable non-prod.

Commands:

```powershell
supabase backups list --project-ref <prod-ref>

$env:DR_EXPORT_LABEL = "prod"
$env:SUPABASE_DB_URL = "<percent-encoded-postgres-url>"
.\tool\dr_export.ps1

$env:DR_RESTORE_TARGET_DB_URL = "<restore-drill-postgres-url>"
.\tool\dr_restore_drill.ps1 `
  -DumpDir "backups/supabase/<timestamp-label>" `
  -ConfirmNonProdTarget `
  -Execute
```

Pass criteria:

- export folder exists with `schema.sql`, `data.sql`, and `manifest.json`
- restore drill completes
- restore target passes representative app/RLS smoke checks
- Storage object-byte gap is tracked until a media export path exists

## Gate 5 - Scenario Sim + k6

Owner: ops run, agent triage if failures appear.

Commands:

```powershell
$env:SUPABASE_URL = "https://<staging-ref>.supabase.co"
$env:SUPABASE_ANON_KEY = "<staging-anon-key>"
$env:SCENARIO_TARGET_LABEL = "staging"
$env:SCENARIO_USER_A_EMAIL = "<user-a>"
$env:SCENARIO_USER_A_PASSWORD = "<password>"
$env:SCENARIO_USER_B_EMAIL = "<user-b>"
$env:SCENARIO_USER_B_PASSWORD = "<password>"
dart run tool/scenario_sim.dart
```

```powershell
$env:K6_TARGET_LABEL = "staging"
$env:K6_VUS = "2"
$env:K6_DURATION = "1m"
k6 run tool/k6/vamo_hot_paths.js
```

Pass criteria:

- scenario simulator returns `"ok": true`
- k6 checks stay above 95%
- k6 `http_req_failed` stays below 5%
- p95 request duration stays below 1500ms at baseline
- one modest ramp, for example `K6_VUS=5 K6_DURATION=3m`, stays green

## Gate 6 - Infra Upgrade

Owner: ops.

Status needed:

- Supabase Pro enabled.
- Vercel Pro enabled or launch account/team decision documented.
- Billing alerts/owner emails checked.

Pass criteria:

- DR gate is unblocked
- public web tier has the intended production account ownership

## Deferred

English-first closed beta defers full i18n. Add target-locale ARB completion
before widening to non-English markets.
