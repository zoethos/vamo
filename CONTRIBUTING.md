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

## Run shortcuts

```
melos run android   # app on the connected Android device (auto-detected)
melos run chrome    # app in Chrome on port 3000 (Supabase redirect-listed)
melos run ci        # codegen + analyze + tests, required ordering
```
