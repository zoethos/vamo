# S32 — Architecture guardrails: import-guard + `app_core` barrel re-layering

**Branch:** `feature/arch-guardrails` **from `main`** · **Est:** ~1–1.5 dev-days
**Depends:** S31 report (`docs/ARCHITECTURE_BOUNDARIES.md`) landed — uses its agreed
sub-barrel taxonomy + pure-file allowlist.
**Why:** these are the two items S31 flags as worth doing **proactively** (low-risk,
high-leverage) instead of opportunistically: a guard that makes "boundaries-first"
*enforced* rather than aspirational, and the `app_core` barrel re-layering that stops
features reaching infrastructure by default.
**Out of scope:** moving any business logic; extracting packages; schema/RPC/UI
behavior changes. **This slice changes exports + adds tests only — zero logic moves.**

## 0. Preflight
- Clean `main`; ignore unrelated dirty WIP; stage only S32 files. No destructive git.
- **No behavior change.** Existing imports must keep working (umbrella back-compat, §2).

## 1. Part A — import-guard test (the keystone)
A deterministic, CI-run check that fails when a module imports a layer it must not.

- **Implementation:** a root script `tool/arch_guard.dart` driven by a declarative
  manifest, plus a thin wrapper so it runs in `melos run ci` (add a `melos`
  custom script `arch-guard` and call it from the `ci` aggregate). Read source
  files with `dart:io`; match `import`/`export` directives. Keep it dependency-light
  (no `analyzer` package needed for line-level import checks).
- **Rules (declarative manifest):** for each guarded directory, list forbidden
  import substrings.
  - **Pure/domain files** (start from the S31 allowlist: `expenses/expense_split.dart`,
    `settle/settle_up.dart`, `expenses/receipt_ocr_parse.dart`,
    `expenses/receipt_ocr_form_prefill.dart`, `fx/fx_math.dart`,
    `plan/event_rsvp_models.dart`, and any others S31 marks "keep pure") must NOT
    import: `package:flutter/` (widgets/material/cupertino), `package:drift/`,
    `package:supabase`, `package:flutter_riverpod/`, platform plugins
    (`image_picker`, `geocoding`, etc.). `dart:` core + pure pkgs only.
  - **Domain layer must not import the infra sub-barrel** (`app_core/infra.dart`,
    §2).
- **Self-test:** include a unit test that plants a known-bad import string through
  the checker and asserts it is **caught** (the guard must fail on violations, not
  silently pass) — plus a clean-case assert.
- **Output:** on violation, print file + offending import + which rule, and exit
  non-zero. Must be greppable in CI logs.

## 2. Part B — `app_core` barrel re-layering
Today `packages/app_core/lib/app_core.dart` (one flat barrel) re-exports
infrastructure (`db/app_database.dart`, `db/database_provider.dart`,
`supabase/supabase_providers.dart`, `storage/*`, `auth/auth_repository.dart`,
`push/*`, `env/env.dart`) **alongside** pure helpers (`fx/fx_math.dart`,
`invites/invite_urls.dart`) and design tokens. So any feature import pulls Drift +
the Supabase client + storage into scope. Re-layer **without breaking anything**:

- **Add three sub-barrels** under `packages/app_core/lib/`:
  - `app_core/design.dart` — `design/*` (tokens, `app_states`, `brand_assets`).
  - `app_core/domain.dart` — pure helpers (`fx_math`, `invite_urls`,
    pure models, `push_notification_route`, etc. — per S31 taxonomy).
  - `app_core/infra.dart` — `db/*`, `supabase/*`, `storage/*`,
    `auth/auth_repository`, `push/push_registrar`, `env/env`, analytics infra.
- **Keep `app_core.dart` as a back-compat umbrella** that re-exports all three, so
  existing `import 'package:app_core/app_core.dart'` keeps compiling — **zero
  breakage**. Mark it `@Deprecated`-style in a doc comment ("prefer the layered
  sub-barrels; umbrella retained for back-compat").
- **Wire the guard (Part A)** so domain/pure files importing `app_core/infra.dart`
  fail CI. This is what gives the re-layering teeth.
- **Do NOT mass-migrate** `feature_split` imports in this slice — migration happens
  opportunistically as slices touch files (per S31 §9). S32 only creates the seams
  + the enforcement.

## 3. Part C — S29 token-adoption ratchet (optional, recommended)
S29 tokens have ~0 downstream adoption (**174 raw `AppColors.` refs / 33 files** in
`feature_split`). A "no new raw `AppColors`" rule is hard to enforce per-diff, so use
a **baseline ratchet** instead:
- Record the current count as a baseline (e.g. `tool/appcolors_baseline.txt`).
- A check (folded into `arch-guard`) **fails if the count increases** above baseline;
  whenever a slice migrates usages to tokens, lower the baseline.
- This chips the 174 down monotonically and blocks regressions, without forcing a
  big repaint now.

## 4. Files
- `tool/arch_guard.dart` (new) + manifest (inline or `tool/arch_guard_rules.dart`)
- `tool/arch_guard_test.dart` or `packages/app_core/test/arch_guard_test.dart` (self-test)
- `melos.yaml` — add `arch-guard` script + call it from `ci`
- `packages/app_core/lib/app_core/design.dart`, `domain.dart`, `infra.dart` (new sub-barrels)
- `packages/app_core/lib/app_core.dart` (umbrella now re-exports the three; doc note)
- `tool/appcolors_baseline.txt` (optional, Part C)

## 5. Verification
- `melos run ci` green, **including** the new `arch-guard` step.
- Guard **self-test passes**: planted bad import is caught; clean case passes.
- **No behavior change:** the full existing test suite passes unchanged (re-layering
  is export-only). `git diff` shows no edits under feature logic/repository files.
- Confirm a real violation is caught end-to-end: temporarily add a `package:drift/`
  import to a pure file locally → `arch-guard` fails → revert.

## 6. Reviewer checklist
- [ ] `arch-guard` runs in `melos run ci` and exits non-zero on violations
- [ ] Self-test proves the guard catches a planted bad import (not a no-op)
- [ ] Pure/domain allowlist matches S31's "keep pure" list
- [ ] Three sub-barrels added; `app_core.dart` umbrella keeps back-compat (nothing breaks)
- [ ] Domain/pure importing `app_core/infra.dart` fails the guard
- [ ] **No business logic moved; no UI/schema/RPC behavior change**
- [ ] (Part C) AppColors ratchet baseline set; increases fail CI
- [ ] Existing test suite passes unchanged

## 7. Commit
`chore(arch): add import-guard + layered app_core barrels`

## Notes
- S32 is the enforcement substrate; the actual domain extractions (S31 §9) ride the
  feature slices that open those files. Guard + seams first means those later
  extractions are checkable the moment they happen.
- Not a Wave-2 gate dimension — schedule behind S29 (+P1), S22, S30, and
  tester-readiness; pick up when there's a refactor-adjacent lull.
