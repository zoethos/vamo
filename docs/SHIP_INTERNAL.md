# Ship to TestFlight & Play internal

Wave 1 internal build after Slice 10 polish. Version in `app/pubspec.yaml` (`version: 0.1.0+1` — bump `+build` each upload).

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
