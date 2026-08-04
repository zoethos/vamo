# Visible environment label for tester/debug builds

## Goal

Make it obvious on device whether the installed Vamo app is connected to
staging or production. Today `flutter run` uses `app/.env`, and both staging and
production builds share the same Android package id (`app.vamo`), so a device can
silently overwrite one with the other.

## Scope

- Add typed environment metadata in `Env`, derived from `SUPABASE_URL`:
  - `sfwziwcuyctxvidivnsh` -> `staging`
  - `mjercplkmuoctdklosyy` -> `production`
  - anything else -> `unknown`
- Show the environment visibly in debug/profile builds:
  - Profile/About: app version + environment + Supabase project ref.
  - Optional lightweight debug banner/chip on the signed-in shell for
    non-production builds only.
- Keep release production clean:
  - No always-on staging badge in `kReleaseMode` production.
  - Unknown environment should be visible in debug/profile and treated as a
    warning state.
- Add a safe startup debug log line:
  - `Vamo env: staging (sfwziwcuyctxvidivnsh)`
  - Never log anon keys, service keys, provider keys, emails, or trip data.

## Out of scope

- No Android/iOS flavor split in this slice.
- No separate package id yet.
- No changes to Supabase Auth redirect configuration.
- No build upload/version bump unless this is folded into a tester build.

## Implementation notes

- Keep `app/.env` as the current runtime selector for now.
- Add a small `VamoEnvironment` value object/pure helper so tests can classify
  project refs without initializing Flutter.
- Suggested visible labels:
  - `STAGING`
  - `PRODUCTION`
  - `UNKNOWN ENV`
- Suggested locations:
  - Profile/About row: `Environment  STAGING · sfwziwcuyctxvidivnsh`
  - Non-production shell chip: small muted `STAGING` pill near the top app shell
    or profile header, not lime.
- The app should never display or log `SUPABASE_ANON_KEY`.

## Architecture decision

**Pure helper + thin UI.** Environment classification is a pure rule derived from
the configured Supabase URL/project ref. UI should only render that value; it
must not infer environment from Supabase CLI link state or Git branch.

## Tests / guardrails

- Unit test: known staging URL resolves to `staging`.
- Unit test: known production URL resolves to `production`.
- Unit test: malformed/unknown URL resolves to `unknown`.
- Widget test: Profile/About shows environment in debug/profile-style test
  configuration.
- Widget test: production release path does not show a persistent debug badge.
- Secret guard: tests assert no key values are rendered.
- `melos run ci` green.

## Done

- A tester can open the installed app and tell staging vs production without
  checking files or terminal history.
- `flutter run` remains simple, but the running app self-identifies its backend.
- The source of truth is explicitly `SUPABASE_URL`, not the linked Supabase CLI
  project.
