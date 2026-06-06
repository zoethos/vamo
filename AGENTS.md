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
