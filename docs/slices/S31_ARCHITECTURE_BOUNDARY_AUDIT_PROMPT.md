# S31 — Architecture boundary & reusability audit (report + governance)

**Branch:** `codex/architecture-boundary-governance` **from `main`** · **Est:** ~1 dev-day
**Type:** report + governance only — **no production code refactor in this slice.**
**Why:** business rules are spread across screens, repositories, edge functions,
sync code, and UI state. Goal: a concrete boundary map + ranked extraction
candidates + a durable guardrail, so future slices stop cloning rules and bypassing
shared logic — **boundaries-first, not package sprawl.**

## 0. Preflight (AGENTS.md)
- Start from a clean `main` on the branch above. The working tree may carry
  unrelated docs/brand WIP — **do not touch, stage, or overwrite it.**
- Stage only S31 files: `AGENTS.md`, `docs/ARCHITECTURE_BOUNDARIES.md`, this prompt.
- No destructive git. No production code changes. No new packages.

## 1. Grounding already done (verify, then extend — don't re-derive from zero)
A planning pass on `feature/design-system-foundation` measured the current shape.
Confirm these on `main` and build the report on top:

- **`app_core` barrel leaks infrastructure.** `packages/app_core/lib/app_core.dart`
  flat-exports `db/app_database.dart`, `db/database_provider.dart`,
  `supabase/supabase_providers.dart`, `storage/*`, `auth/auth_repository.dart`,
  `push/*`, `env/env.dart` **alongside** pure helpers + design tokens. One
  `import 'package:app_core/app_core.dart'` puts Drift + the Supabase client +
  storage in scope everywhere. **This is the #1 coupling enabler.**
- **Pure islands already exist (protect them):** `expenses/expense_split.dart`
  (47L), `settle/settle_up.dart` (96L), `expenses/receipt_ocr_parse.dart` (268L),
  `expenses/receipt_ocr_form_prefill.dart` (69L), `fx/fx_math.dart`,
  `plan/event_rsvp_models.dart` (102L) — verified **no** Flutter/Drift/Supabase/
  Riverpod imports.
- **Mixed hotspots (the targets):** `expenses/add_expense_screen.dart` (729L),
  `expenses/expenses_repository.dart` (706L), `plan/plan_repository.dart` (614L),
  `trips/trips_repository.dart` (516L), `settle/settlements_repository.dart`
  (303L) — domain policy blended with Drift/Supabase/sync/analytics.
- **Lifecycle gates are only *partly* pure:** `trips/trip_lifecycle_actions.dart`
  (246L) mixes gate policy with Flutter+Riverpod — the policy needs lifting out.
- **Edge functions don't share:** `supabase/functions/resolve-theme/index.ts` is
  **867L**, there is **no `_shared/` dir**, and each function re-implements JWT
  verify / CORS / error shaping / provider-resilience.
- **S29 tokens have ~0 downstream adoption:** **33 files / 174 raw `AppColors.`
  refs** in `feature_split` still bypass the new theme extensions.

## 2. Part A — governance rule (edit `AGENTS.md`)
Insert this section **after `## Quality Gates`** (before `## Merge, Push, And Cleanup`):

```markdown
## Architecture And Business Logic Governance

For every feature slice, agents must decide where business logic belongs —
a reusable pure module, a service, an adapter, or (rarely) a package — instead of
inlining it in screens, widgets, repositories, edge functions, or one-off helpers.

Before implementing, check whether the change introduces:
- repeated business rules or calculations (clone risk)
- UI code making product-policy decisions
- repositories mixing domain rules with Drift, Supabase, sync, storage, or analytics
- direct platform/provider dependencies where a gateway/adapter would isolate them
- a rule implemented in Dart that is *also* enforced server-side (RLS/RPC/edge) —
  name the single source of truth and avoid silent client/server drift
- bulky code where a lightweight pure function would be easier to test

Prefer:
- pure Dart/TS logic for rules, calculations, validation, grouping, state
  transitions, and permission decisions
- thin UI that renders state and delegates decisions
- repositories that orchestrate persistence/network/sync — not product policy
- small provider/platform adapters at dependency boundaries

Extraction discipline (avoid the opposite failure — premature abstraction):
- **Default = inline pure helper** in the existing package.
- Promote to a **new package only** when a module is pure, tested, stable, AND
  reused by ≥2 surfaces or it isolates a heavy dependency. Package extraction is
  the justified exception, not the reflex. Do not create package sprawl.

Every feature-slice handoff must state the architecture decision —
**"inline" / "pure helper" / "adapter/gateway" / "package candidate"** — with a
one-line reason.
```

## 3. Part B — produce the report (`docs/ARCHITECTURE_BOUNDARIES.md`)
A written report only. Cross-reference (don't duplicate) the existing root
`ARCHITECTURE.md` "Repository growth path" section, `docs/CONVENTIONS.md`,
`docs/DEPENDENCIES.md`. Required sections:

1. **Dependency map** — `app` → `app_core` / `feature_split`; what `feature_split`
   reaches in `app_core`; web; `supabase/functions`. Call out the `app_core`
   barrel infra-leak explicitly.
2. **Business-logic leakage inventory** — concrete files/functions where domain
   policy is mixed into screens / repositories / edge functions (use the §1 list,
   verify, extend).
3. **Pure islands to protect** — the §1 list + any others; mark each "keep pure".
4. **Cross-language duplication (robustness)** — for settlement permissions,
   lifecycle gates, split validation: where is the rule *also* in RLS/RPC? Decide
   single source of truth (client computes / server authoritatively checks) and
   note needed cross-checks. **Money correctness is the trust veto — treat this
   as the highest-stakes finding, above file size.**
5. **`app_core` barrel re-layering** — proposal to split the flat barrel into
   layered sub-barrels (e.g. `app_core/design.dart`, `app_core/domain.dart`,
   `app_core/infra.dart`) so infra access is explicit + greppable + guard-testable.
   Low-risk (export reshaping, not code moves) — flag as an early high-leverage win.
6. **Edge-function `_shared/` boundary** — propose `supabase/functions/_shared/`
   (auth-verify, cors, json-error, a `PROVIDER_RESILIENCE` wrapper) reconciled with
   the per-function `deno.json` hygiene rule (shared via relative import; each
   function keeps its own `deno.json` + frozen lock). Flag `resolve-theme` (867L)
   as the first decomposition target.
7. **Package/library candidates — ranked by value/risk/timing:**
   - `vamo_money` — cents, FX conversion, split validation, balances, settlement
     math. **Strongest first candidate** (math already pure). Note its server-side
     counterpart (§4).
   - **`vamo_postcard`** — place→visual backdrop across receipt/note/photo/video;
     isolates the photo/map provider dependency. **Already a validated candidate**
     (see `docs/POSTCARD_SPEC.md`) — include it.
   - `vamo_design` — after S29/S28 stabilize + downstream adoption climbs (174 raw
     `AppColors` refs today).
   - trip lifecycle / permissions — after the policy is lifted from
     `trip_lifecycle_actions.dart`.
   - `vamo_platform` — only if plugin adapters keep spreading.
   - web/admin provider-cost-env shared package — only once the admin dashboard
     starts.
8. **"Do not extract yet" list** — what would be premature, and why.
9. **Recommended execution strategy (important):** do **not** run a standalone
   big-bang refactor wave. **Fold each extraction into the slice that already opens
   that file** — e.g. extract settlement math when **S22** touches the close
   report; extract plan grouping/reorder when **S30**/plan work touches it. Lower
   blast radius, amortized, no merge-conflict war with parallel feature work, no
   stall on the Wave-2 gate. The two exceptions worth doing proactively because
   they're low-risk and high-leverage: the **`app_core` barrel re-layering (§5)**
   and the **import-guard test (§10)**.
10. **Guardrail — the keystone.** Recommend a directory-allowlist **import-guard
    test** that fails `melos run ci` if a domain/pure module imports Flutter
    widgets, Drift, Supabase, or Riverpod. Extend it to flag raw `AppColors`/
    `EdgeInsets` in newly-touched component files (gives S29 tokens teeth, chips at
    the 174 refs). This is what makes "boundaries-first" durable instead of
    aspirational. (Recommend in the report; the guard test itself is the natural
    **first follow-up implementation slice**, since it's additive and safe.)
11. **Money-refactor safety rule** — any move of `settle_up`/split/balances code
    must be **characterization-test-gated**: pin current outputs (known inputs →
    snapshot exact cents/ordering) **first**, then move behind them. Behavior-
    preserving by construction.

## 4. Constraints
- Report + `AGENTS.md` edit only. **No** production code, **no** new packages,
  **no** schema/RPC changes, **no** destructive git.
- Treat current dirty working-tree files as unrelated unless they belong to S31.
- Recommendations prefer pure logic + thin adapters over generic frameworks.
- Plan must be independent — pickable later without blocking S28/S29 (incl. the
  S29 P1 teal-contrast fix), S22, S23 follow-ups, S30, or tester-readiness.

## 5. Verification
- `git diff --check` clean; `git status -sb --untracked-files=all` names only S31
  files staged + lists remaining unrelated dirty files.
- Docs-only — no app tests required. (If the optional guard test is added, it must
  pass `melos run ci`; otherwise leave it as a recommendation.)
- Handoff states: branch, files changed, "no production code changed".

## 6. Commit
`docs: add architecture boundary governance + audit report`

## Notes / sequencing
- This is internal robustness, **not** a Wave-2 gate dimension — it must not jump
  ahead of closing S29 (+P1) or the remaining functional slices.
- The report is cheap; the *execution* is not — that's why §9 ties execution to
  slices already in flight rather than a dedicated refactor wave.
