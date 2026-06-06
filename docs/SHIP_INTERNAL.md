# Ship to TestFlight & Play internal

Wave 1 internal build after Slice 10 polish. Version in `app/pubspec.yaml`
(`version: 0.1.0+1` — bump `+build` by exactly 1 each upload). Android
renders this as tester-visible `versionName 0.1.0.1`.

## Pre-flight

```bash
melos bootstrap
melos run build_runner
melos run test
melos run analyze
```

- [ ] `app/.env` production values (Supabase URL + anon key only — never service role).
- [ ] `POSTHOG_API_KEY` set for analytics QA ([RUN.md](../RUN.md) Slice 10).
- [ ] **`dart run tool/rls_smoke.dart` PASS** on cloud ([RLS_QA.md](RLS_QA.md)) — required before any store upload.
- [ ] RLS QA manual appendix complete if needed ([RLS_QA.md](RLS_QA.md)).
- [ ] Deep links configured per `app/README_DEEP_LINKS.md` (optional for first internal).
- [ ] iOS photo permission string in `app/README_PLATFORM.md`.

## iOS — TestFlight

1. Open `app/ios` in Xcode (or `flutter build ipa` after `flutter create` platform folders exist).
2. Set **Bundle ID**, signing team, and increment build number.
3. Archive → Distribute → App Store Connect → TestFlight.
4. Add internal testers in App Store Connect.

```bash
cd app
flutter build ipa --release
```

## Android — Play internal testing

1. Create app in Google Play Console (internal testing track).
2. Upload AAB:

```bash
cd app
flutter build appbundle --release
```

3. Add internal testers by email list.

## Post-upload QA (device)

| Flow | Analytics event |
|------|-----------------|
| Create trip | `trip_created` |
| Invite share | `member_invited` |
| Second account joins | `invite_accepted` |
| Add expense | `expense_added` |
| Mark settle | `settle_marked` |
| Confirm settle | `settle_confirmed` |
| Share snapshot (complete share) | `snapshot_shared` |

Verify in PostHog **Live events** (or debug console if key unset).

**Product signals (Slice 11 / T11.6):** confirm every named screen fires `screen_viewed` in PostHog Activity; trigger trips-list sync failure and verify `error_shown` includes `kind`; trigger a write failure (e.g. temporarily break RPC) and verify `action_failed` includes `screen`, `action`, `kind`, and sanitized `code` (e.g. `PGRST202` — never raw exception text); spot-check one intentional `flow_abandoned` (e.g. add expense) but not after a completed invite share; one intention door + `suggestion_submitted`; cloud suggestions RLS ([RLS_QA.md](RLS_QA.md)). `notify_me_opted_in` is analytics-only until map/recap ship.

## Known Wave 1 limits (document for testers)

- Trip create / join still use immediate RPC (not outbox).
- Settlement revoke uses direct remote write.
- Push notifications not included (stretch cut).

---

# Wave 2 internal build (S15–S19) — go/no-go

First internal build carrying QR invite, roles+push, trip lifecycle, TripBoard,
and money governance I. Bump `app/pubspec.yaml` to `0.2.0+N` (Wave-2 line).
Each upload increments `+N` by exactly 1; Android/Profile show it as
`0.2.0.N` so tester screenshots and reports identify the exact build.

## Gate (all required before upload)
- [ ] `main` CI green at the build commit (build_runner + analyze + test).
- [ ] `dart run tool/rls_smoke.dart` **PASS on cloud** (currently 51/51) — the
      release gate; never upload on a red smoke.
- [ ] `app/.env` production values (Supabase URL + anon key only — never service role).
- [ ] Migrations 0001–0018 applied to the cloud project (`supabase migration list`
      shows local == remote).

## Android identity / deep links (do for this build, not deferred)
- [ ] Real `assetlinks.json` SHA-256: `cd app && ./gradlew signingReport`, take
      the **upload key** SHA-256, replace `DEBUG_FINGERPRINT` in
      `web/apps/site/public/.well-known/assetlinks.json`, redeploy site. Add the
      Play App Signing cert SHA-256 too once the Play app exists (both may be
      needed during transition). Verifies App Links so QR/invite opens the app
      directly, not the browser.
- [ ] `google-services.json` present at `app/android/app/` (package `app.vamo`) ✓ (S16).

## S16 manual tail (hardware-bound — only you)
- [ ] `melos run android` rebuild on the S25 — carries the whole stack
      (overview, logos, deep-link fix, lifecycle banner, governance UI).
- [ ] Dashboard → Edge Functions → `scheduled-heartbeat` → hourly cron `0 * * * *`
      (the harmless no-op; this one SHOULD be scheduled).
- [ ] Device push test per RUN.md Slice 16: sign in → background → curl
      `send-push` → tap opens trip route.

## Build & upload (Android Play internal)
```bash
cd app
flutter build appbundle --release
```
Upload AAB to Play Console internal-testing track; add testers by email.

## Wave 2 known limits (document for testers)
- **Trip auto-close does NOT fire yet** — `trip-lifecycle-jobs` is deployed
  but unscheduled (gated on S22 push: "no notice, no deemed consent"). Owners
  can still request/force close manually; the 14-day deemed-close and 6-month
  unresolved jobs are dormant until S22.
- **Governance actions are online-only** — propose / commit / void / dispute
  call RPCs directly (no offline outbox). Born-committed expense logging stays
  offline-first.
- **Close report UI not built** (S22) — close works, but the reconciliation
  report (deemed vs explicit, FX drift, consent ledger) lands later.
- Budget + FX constant-rate table not in this build (S20).

## Post-upload QA
Wave-1 analytics table above still applies, plus spot-check the new funnel
events in PostHog Live: `qr_shown`, `close_requested`/`close_accepted`,
`plan_item_created`, `proposal_created`/`share_response` (structure only — no
amounts/reason text).
