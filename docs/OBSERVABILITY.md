# Observability & Telemetry Standards

Effective 2026-06-08. Goal: **no failure is ever hard to diagnose again.** The
trip-background bug took days only because the error was *swallowed* and *collapsed
to "unknown"* — both are now banned. Debug builds must make the real error obvious;
release builds stay sanitized (no PII/secrets) per the error policy.

## Principles
1. **Never swallow.** A bare `catch (_) {}` or `catch (e) {}` with an empty/silent
   body is forbidden in `lib/`. Every catch either rethrows or calls the logging
   helper. (The `setTripBackground` `catch (_)` that hid the real error is the
   anti-pattern.)
2. **Every error carries context** — `{screen, action}` at minimum, so a failure is
   self-locating.
3. **Classify everything; "unknown" is a bug, not a default.** Every catch path maps
   to a specific kind. If you see "unknown" in the wild, the classifier is missing a
   case — fix the classifier, don't ship the mystery.
4. **Debug shows the truth, release shows the catalogue.** Debug builds print the
   raw error + **stack trace** + context; release reports a sanitized, catalogued
   code to PostHog and a friendly message to the user.

## The one helper
All error handling routes through a single helper (extend the existing
`reportActionFailed` / `showActionError`):

```dart
reportAndLog(error, stackTrace, {required screen, required action})
  // debug:   debugPrint('[$screen/$action] $error\n$stackTrace')  + breadcrumb
  // release: PostHog action_failed { screen, action, error_kind, error_code }  (no PII)
```
- `kDebugMode` gates the verbose path. Never log raw errors to analytics in release
  (sanitize via `sanitizeActionFailureCode`).
- Swallowed-but-non-fatal paths (e.g. "remote unavailable, local still works") MUST
  still call this with a `severity: degraded` — log it, don't drop it.

## Classifier coverage (close the gaps)
`classifyActionFailureKind` / `sanitizeActionFailureCode` must recognize, at minimum:
- `FileSystemException` → `file_error`
- sqlite **and Drift-wrapped** exceptions → `db_error` (today `_isSqliteException`
  misses Drift wrappers → those fall to "unknown")
- Flutter framework / Navigator / `StateError` / assertion → `app_error`
- `PostgrestException` (incl. function-not-found) → `server`
- `AuthException` → `auth`; `StorageException` → by status
- network / timeout → `network`
- only genuinely-unrecognized → `unknown` (and that should be rare enough to alert on)

## Debug-build observability
- **Breadcrumbs** for high-value flows (capture, background, sync, RPC calls,
  lifecycle): log entry/exit + key params (no PII) so a failure has a trail.
- **Raw provider/RPC errors** logged in full in debug (PostgREST message, RPC name,
  storage path) — the things that make "(unknown)" diagnosable in one run.
- Optional: a debug-only on-screen error surface (full message + "copy") so device
  testing doesn't require a console.

## Enforcement
- **Guard test / grep check** in `melos run ci`: fail if `lib/` contains a bare
  `catch (_)` or an empty catch body. (Pairs with the S31/S32 import-guard.)
- A telemetry test asserting `reportAndLog` fires `action_failed` with `error_kind`
  set (never empty/unknown for the catalogued types above).
- PR checklist line: "every new catch logs via `reportAndLog`; no silent swallow;
  error classified."

## Why this matters
Today's failures (`(unknown)` background error, the swallowed remote upload) were
*invisible*, so three agents pattern-matched and missed. With this standard the next
failure prints `[trip_home/set_trip_background] NavigatorException … at line N` on the
first cold run — minutes, not days.
