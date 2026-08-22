# Cycle 2 Launch Gates

This is the public-v1 eligibility checklist. Code for the feature batch can be
merged while these are open, but closed beta should not widen until every gate
below is green.

## Status as of 22 August 2026

Established by a read-only audit (repo, CI, `supabase secrets list`, `supabase backups
list`, Vercel team plan). **Update this table whenever a gate moves**; a gate is green only
when its own pass criteria below are evidenced, not when its prerequisites are in place.

| # | Gate | Status | What is proven | What is still missing |
| --- | --- | --- | --- | --- |
| 1 | Email SPOF closed | **Open — nearly done** | `RESEND_API_KEY` and `RESEND_SENDER_EMAIL` are set in **both** Staging (`sfwziwcuyctxvidivnsh`) and Production (`mjercplkmuoctdklosyy`), with identical digests. `send-auth-email` is ACTIVE in Production (v21). | The forced-fallback proof on staging has never been run/recorded. **Also a Production config defect — see below.** |
| 2 | Crashlytics proof | **Open** | Crashlytics is wired in the Android app. | No recorded forced-crash event tied to a tester build version. Device QA fact — owner. |
| 3 | App Links SHA | **Open — repo side done** | `web/apps/site/public/.well-known/assetlinks.json` carries two SHA-256 fingerprints, added in `3e1f5cc` (20 June 2026). | No recorded device proof that an invite link opens the installed app, and no record of which fingerprint is the Play app-signing key vs the upload key. |
| 4 | DR basics | **Open — partly proven** | Supabase daily `PHYSICAL` backups are `COMPLETED` in Production, unbroken through 2026-08-22 (which also evidences a paid Supabase plan). | PITR not confirmed; no logical export exists (`backups/` is absent from the repo and nothing is recorded off-site); the restore drill has never been run. |
| 5 | Scenario sim + k6 | **Open** | The runbook and both harnesses (`tool/scenario_sim.dart`, `tool/k6/vamo_hot_paths.js`) exist and are ready to run against Staging. | No run has ever been recorded, so no baseline exists for any pass criterion. |
| 6 | Infra upgrade | **Open** | Supabase Production is on a paid plan (daily physical backups). | **Vercel is on the `hobby` plan** (team `tizianos-projects-96dfeb3a`) and no launch account/ownership decision is documented. Billing alerts unchecked. |

**None of the six gates is green, so closed beta must not widen.** Gates 1, 3 and 4 are the
closest — each is blocked only on running and recording a proof, not on building anything.

### Production defect found during this audit — `send-auth-email` config

Production secrets do **not** contain `BREVO_API_KEY` or `SEND_EMAIL_HOOK_SECRET`, which the
deployed function requires (`supabase/functions/send-auth-email/index.ts`,
`email_providers.ts`). Production instead carries a secret whose *name* is
`ad9aa9001@smtp-brevo.com` — the shape produced by a malformed `supabase secrets set`, where
an SMTP login became the key name. Staging has both variables set correctly.

This means one of two things, and the owner must determine which before Gate 1 can close:

1. **The Auth email hook is not enabled in Production.** Auth mail then goes through
   Supabase's own SMTP settings, the deployed `send-auth-email` is dead code in Production,
   and the Brevo→Resend fallback the gate is about does not protect Production at all.
2. **The hook is enabled.** Then `SEND_EMAIL_HOOK_SECRET` is empty, so hook verification
   cannot succeed and Brevo has no key — a live auth-email outage.

Production sign-in is believed to work, which points at (1). Either way the stray
`ad9aa9001@smtp-brevo.com` secret should be removed and the intended path made explicit.
Do not change Production Auth or secrets from this audit; it is read-only by design.

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

1. In Play Console, open **Protected with Play** -> **Play Store
   distribution** -> **Go to Play app signing**, then scroll to **App signing
   key** and copy the SHA-256 fingerprint.
2. Patch `web/apps/site/public/.well-known/assetlinks.json`.
3. Redeploy the site.
4. Install the Firebase App Distribution tester build and open an invite/QR
   link.

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

If `k6` is not installed locally, run the same script through Docker:

```powershell
docker run --rm `
  -e K6_TARGET_LABEL `
  -e K6_VUS `
  -e K6_DURATION `
  -e SUPABASE_URL `
  -e SUPABASE_ANON_KEY `
  -e RLS_USER_A_EMAIL `
  -e RLS_USER_A_PASSWORD `
  -e RLS_USER_B_EMAIL `
  -e RLS_USER_B_PASSWORD `
  -v "${PWD}\tool\k6:/scripts" `
  grafana/k6 run /scripts/vamo_hot_paths.js
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
