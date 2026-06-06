# Development policy

Effective from v0.1.0 (June 2026). Solo-founder + AI-agents workflow — rules
are few but enforced.

## Versioning

- Semantic-ish, starting at **0.1.0**. Increments are **manual** decisions,
  marked with annotated git tags on `main`:
  ```
  git tag -a v0.1.0 -m "Wave 1 code-complete"
  git push origin v0.1.0
  ```
- Bump `version:` in `app/pubspec.yaml` in the same commit as the tag
  (build number `+N` increments on every store upload).
- Minor (0.X) = a slice or feature lands; patch (0.x.Y) = fixes only.
  1.0.0 = first public store release.

## Branching

- **Features**: branch `feature/<name>` from `main`; merge back when the
  feature is done and `melos run ci` is green. Use `--no-ff` so the merge
  commit marks the feature boundary:
  ```
  git switch -c feature/themes-ai-resolver
  # ... work ...
  git switch main && git merge --no-ff feature/themes-ai-resolver
  git push && git branch -d feature/themes-ai-resolver
  ```
- **Fixes & small changes** that belong to no feature: commit directly to `main`.
- Never rewrite history on `main` (no force-push).

## Quality gates

- `melos run ci` (codegen → analyze → test) must pass before any merge to `main`.
- Every push to `main` (including merge pushes) triggers **automated Claude
  code review** (`.github/workflows/claude-review.yml`) — findings appear as
  commit comments. P1 findings get fixed before the next feature branch opens.
- Schema changes only as numbered files in `supabase/migrations/`, applied
  with `supabase db push`.

## Testing

- **RLS smoke** (`tool/rls_smoke.dart`): cases are state-based — **no error ≠
  it worked**. Assert the post-condition (row absent, lifecycle unchanged, write
  blocked), not merely that the RPC didn't throw.
- **External-provider smoke makes at most one live call per provider.** Live
  calls prove the endpoint + secret path; invariants that need repeated states
  use deterministic stubs or service-role writers instead of hammering the
  upstream and burning quota.
- **Realtime/offline slices need a propagation contract.** When one client
  writes and another client should see it, tests must cover more than SQL/RLS:
  prove remote data reaches local Drift, providers/UI render it, trip-scoped
  bindings refresh on mount, unsubscribe on dispose, and refresh again on
  remount. RLS smoke should mirror the user-facing direction from the manual
  acceptance script; green direct SQL alone is not merge-ready.
- **UI and SQL tests**: **Tests must assert the negative.** A UI/SQL test
  proves the control is hidden, the route bounces, the write is blocked, or
  the error path did not fire — not merely that a helper returns false or a
  mock was called once. "CI green" only counts when the test would fail if the
  guard were removed.
- **`SECURITY DEFINER` re-checks membership.** A definer function bypasses RLS,
  so any definer reader/aggregate granted to `authenticated` MUST re-check
  `is_trip_member` (or tighter) internally — otherwise it leaks other trips'
  data. Every definer reader gets an outsider-blocked smoke case. (S20 caught a
  spend-totals leak from a definer aggregate that skipped this.)

## Run shortcuts

```
melos run android   # app on the connected Android device (auto-detected)
melos run chrome    # app in Chrome on port 3000 (Supabase redirect-listed)
melos run ci        # codegen + analyze + tests, required ordering
```
