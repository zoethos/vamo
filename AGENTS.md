# AI Agent Git & GitHub Rules

This repo uses solo-founder + AI-agent development. These rules are mandatory
for Codex, Cursor, Claude, review bots, and any other agent touching the repo.

## Preflight

1. Start every task with:
   ```powershell
   git status -sb --untracked-files=all
   git branch --show-current
   git stash list --max-count=5
   ```
2. If work is already dirty, identify which changes belong to the current task
   and which are unrelated. Never overwrite or revert unrelated user work.
3. Work from the right base:
   - Feature slices: `feature/<slice-or-feature-name>` from `main`.
   - Fixes: `fix/<short-name>` from `main`.
   - Agent/doc chores: `codex/<short-name>` from `main`.
4. Do not keep working on a stale feature branch after it has been merged.

## Staging And Stashes

1. Prefer no stash when possible. It is safe to leave unrelated local changes in
   the working tree and stage only the files for the current task.
2. Never run a blanket `git stash` or `git stash -u` as a convenience step.
   Blanket stashes can sweep up the feature under review, untracked helpers, or
   unrelated user work.
3. If a stash is truly needed, make it path-scoped:
   ```powershell
   git stash push -u -m "unrelated-wip before <task>" -- <path1> <path2>
   ```
4. After creating a stash, inspect it:
   ```powershell
   git stash list --max-count=3
   git stash show --name-status --include-untracked "stash@{0}"
   ```
5. Do not blindly `git stash pop`. Restore only the paths needed, or pop only
   after checking that the stash does not reintroduce already-merged files.

## Secrets And Sensitive Files

Before every commit, confirm secrets are still ignored and not staged:

```powershell
git status --short --untracked-files=all --ignored |
  rg "key\.properties|\.jks|\.keystore|\.p8|\.pem|service-account|adminsdk|credentials"
git diff --cached --name-only |
  rg "key\.properties|\.jks|\.keystore|\.p8|\.pem|service-account|adminsdk|credentials"
```

Expected: signing keys may appear as ignored (`!!`) only. They must never appear
as staged, modified, added, or untracked files.

## Commit Scope

1. Stage intentionally. Use explicit paths or interactive staging; do not use
   `git add .` unless the status has been audited and every file belongs to the
   task.
2. Run:
   ```powershell
   git diff --cached --name-status
   git diff --cached --check
   ```
3. For critical files that were easy to miss, verify after commit:
   ```powershell
   git show --stat --oneline HEAD
   ```
4. Commit messages should name the slice or purpose, for example:
   - `feat(s26): add contact invite flow`
   - `fix(s21): harden plan RSVP propagation`
   - `docs: add agent git workflow rules`

## Tester Build Versioning

For any tester/store build, bump `app/pubspec.yaml` by exactly one release
counter:

```yaml
version: 0.2.0+7
```

The Android build exposes this as `versionName 0.2.0.7` and `versionCode 7`.
Profile/About should show the clean four-part version, so testers can identify
the exact build without ambiguity. Do not upload two builds with the same `+N`.

## Quality Gates

Before merging to `main`:

1. Run `melos run ci`.
2. For native Android/iOS, platform channels, manifests, Gradle, R8, or app
   signing changes, also run the relevant native build.
3. For Supabase migrations/RPC/RLS changes, run cloud RLS smoke after
   `supabase db push`.
4. For realtime/offline features, test the cross-device propagation path.
5. For platform features that depend on OS behavior, do the real-device pass
   before merge. Compile is not enough. Examples:
   - Android contact picker and SMS/mail composer.
   - Push notification receipt.
   - Deep-link opening into the installed app.

## Architecture And Business Logic Governance

For every feature slice, agents must decide where business logic belongs -
a reusable pure module, a service, an adapter, or (rarely) a package - instead
of inlining it in screens, widgets, repositories, edge functions, or one-off
helpers.

Before implementing, check whether the change introduces:
- repeated business rules or calculations (clone risk)
- UI code making product-policy decisions
- repositories mixing domain rules with Drift, Supabase, sync, storage, or
  analytics
- direct platform/provider dependencies where a gateway/adapter would isolate
  them
- a rule implemented in Dart that is also enforced server-side (RLS/RPC/edge) -
  name the single source of truth and avoid silent client/server drift
- bulky code where a lightweight pure function would be easier to test

Prefer:
- pure Dart/TS logic for rules, calculations, validation, grouping, state
  transitions, and permission decisions
- thin UI that renders state and delegates decisions
- repositories that orchestrate persistence/network/sync - not product policy
- small provider/platform adapters at dependency boundaries

Extraction discipline (avoid the opposite failure - premature abstraction):
- Default = inline pure helper in the existing package.
- Promote to a new package only when a module is pure, tested, stable, and
  reused by 2+ surfaces or it isolates a heavy dependency. Package extraction is
  the justified exception, not the reflex. Do not create package sprawl.

Every feature-slice handoff must state the architecture decision -
"inline" / "pure helper" / "adapter/gateway" / "package candidate" - with a
one-line reason.

## Merge, Push, And Cleanup

1. Merge finished feature/fix branches into `main` with `--no-ff`:
   ```powershell
   git switch main
   git merge --no-ff <branch> -m "merge: <slice or feature>"
   git push origin main
   ```
2. Delete only merged branches with safe delete:
   ```powershell
   git branch -d <branch>
   ```
   Use `-D` only after explicitly confirming the branch is intentionally
   abandoned or already merged elsewhere.
3. After push, final status must be clean or the remaining work must be named:
   ```powershell
   git status -sb --untracked-files=all
   git stash list --max-count=5
   ```
4. If GitHub reports Dependabot, secret-scan, CI, or review findings on push,
   mention them in the handoff and open/fix a follow-up branch as needed.

## Agent Handoff

Every agent handoff must include:

- Current branch and clean/dirty state.
- Commit SHA(s) created.
- Tests/smokes/device checks run.
- Stash names and exact contents if any stash remains.
- Branches deleted or still open.
- Any GitHub warnings or failed checks.
