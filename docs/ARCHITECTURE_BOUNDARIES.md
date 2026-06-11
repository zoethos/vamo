# Architecture Boundaries And Reusability Audit

Status: S31 report and governance only. No production code, schema, RPC, or
package changes are included here.

This report extends the repository growth path in `ARCHITECTURE.md`, plus the
rules in `docs/CONVENTIONS.md` and `docs/DEPENDENCIES.md`. Its job is to make
boundary choices concrete enough that future slices can extract logic when they
already touch the relevant files, without starting a broad refactor wave.

Measurements below were verified on `main` from
`codex/architecture-boundary-governance`.

## 1. Dependency Map

Current client shape:

- `app/` is the native Flutter shell. It depends on `app_core` and
  `feature_split`.
- `packages/app_core/` is meant to hold cross-cutting foundations: auth,
  database, sync, analytics, routing, design, locale, storage, FX, push, and
  lifecycle primitives.
- `packages/feature_split/` contains the Wave 1 product surface and reaches most
  foundations through `package:app_core/app_core.dart`.
- Future `feature_*` packages should be siblings of `feature_split`; features
  depend on `app_core`, never on each other.
- `web/` should remain a separate surface until an admin/operator track needs a
  shared package contract.
- `supabase/functions/` is the TypeScript edge boundary. It is not a Dart
  package boundary, but it enforces and duplicates some of the same product
  policy as the Flutter client and migrations.

The main coupling risk is the flat `app_core` barrel:
`packages/app_core/lib/app_core.dart` exports design primitives, pure helpers,
and domain constants alongside Drift, Supabase providers, storage, sync, push,
auth, router, environment, and analytics. One import of
`package:app_core/app_core.dart` brings both product-neutral helpers and
infrastructure dependencies into scope. That makes it easy for screens and
repositories to reach directly for persistence or platform services instead of
going through a narrower rule module or adapter.

The rule from `ARCHITECTURE.md` still holds: sibling features should depend on
`app_core`, not on each other. The missing enforcement is that `app_core` needs
layered entry points so infra access is explicit and greppable.

## 2. Business Logic Leakage Inventory

These are the highest-value places to avoid adding more product policy inline.
Line counts are current measurements on `main`.

- `packages/feature_split/lib/src/expenses/add_expense_screen.dart` - 739 lines.
  UI owns amount parsing, currency selection, FX state, split interaction,
  lifecycle read-only checks, OCR prefill application, consent surfaces, and
  repository submission choreography. Future expense work should lift validation
  and state transitions into pure helpers before expanding this screen.
- `packages/feature_split/lib/src/expenses/expenses_repository.dart` - 736
  lines. It mixes Drift writes, Supabase writes, sync enqueueing, analytics,
  receipt storage, FX conversion, share payload construction, and consent/update
  rules. Keep persistence orchestration here, but move money math and product
  policy into pure modules with characterization tests.
- `packages/feature_split/lib/src/plan/plan_repository.dart` - 614 lines. It
  combines event CRUD, ordering/grouping, RSVP sync, Supabase writes, and local
  persistence. RSVP value objects are already pure; ordering and mutability
  policy are the next candidates to isolate when plan work resumes.
- `packages/feature_split/lib/src/trips/trips_repository.dart` - 683 lines. It
  coordinates trip CRUD, membership, lifecycle RPCs, invitations, sync, and
  analytics. Keep network/database orchestration here, but avoid adding more
  lifecycle or permission decisions inline.
- `packages/feature_split/lib/src/settle/settlements_repository.dart` - 303
  lines. It already uses pure `settle_up.dart`, but still owns payer/recipient
  status transitions, local/remote settlement writes, sync, and analytics.
  Settlement permissions need explicit server-authoritative cross-checks.
- `packages/feature_split/lib/src/trips/trip_lifecycle_actions.dart` - 246
  lines. Lifecycle gate policy is partly pure in `app_core`, but this file still
  blends Flutter/Riverpod UI state, user-facing action labels, RPC calls, and
  action availability. Lift policy before adding more close/cancel controls.
- `supabase/functions/resolve-theme/index.ts` - 867 lines. Provider selection,
  retry/fallback policy, response shaping, CORS, errors, auth/client setup, and
  destination-theme business behavior live in one file. This is the first edge
  decomposition target.
- `supabase/functions/fx-rates/index.ts`, `send-push/index.ts`, and
  `trip-lifecycle-jobs/index.ts` share some concerns but still keep per-function
  CORS, auth, JSON response, and error-shaping patterns close to the handler.

Do not treat file size alone as the reason to extract. The extraction trigger is
policy that can drift, calculations that need exact tests, or provider/platform
code that should sit behind a gateway.

## 3. Pure Islands To Protect

These modules are already good examples. Keep them free of Flutter widgets,
Drift, Supabase, Riverpod, storage, analytics, and platform/plugin imports.

- `packages/feature_split/lib/src/expenses/expense_split.dart` - 47 lines, keep
  pure. It is the natural home for split validation and rounding behavior.
- `packages/feature_split/lib/src/settle/settle_up.dart` - 96 lines, keep pure.
  It is deterministic integer money math and already mirrors Postgres balance
  semantics.
- `packages/feature_split/lib/src/expenses/receipt_ocr_parse.dart` - 281 lines,
  keep pure. OCR parsing should stay testable without camera, storage, or UI.
- `packages/feature_split/lib/src/expenses/receipt_ocr_form_prefill.dart` - 69
  lines, keep pure. It turns parsed receipt facts into form state.
- `packages/app_core/lib/src/fx/fx_math.dart` - 24 lines, keep pure. This should
  remain the smallest shared FX arithmetic surface.
- `packages/feature_split/lib/src/plan/event_rsvp_models.dart` - 102 lines, keep
  pure. RSVP state and display semantics should stay independent from Riverpod
  providers and repositories.
- `packages/app_core/lib/src/trips/trip_lifecycle.dart` - keep pure where it
  already defines lifecycle states, read-only semantics, phase resolution, and
  close-review date helpers.
- `packages/feature_split/lib/src/trips/close_report_models.dart` - keep pure.
  Close consent display state is a good candidate to remain model-only while the
  screen handles rendering.

Each of these should be covered by the proposed import-guard test before they
grow. That guard matters more than package extraction.

## 4. Cross-Language Duplication And Robustness

Money correctness is the trust veto. When money behavior moves, the first
question is not "where is the file cleaner?" but "which side is authoritative,
and how do we prove Dart and Postgres still agree?"

Current high-stakes duplication:

- Settlement balances: Dart has `settle_up.dart` and repository-side settlement
  totals. Postgres has `trip_balances` and settlement tables from
  `supabase/migrations/0001_wave1_init.sql`. The server is authoritative for
  stored balances and visibility; the client computes previews and offline UI.
  Any move needs characterization tests that pin exact cents and ordering first.
- Split validation: Dart has `expense_split.dart`; Postgres migrations include
  share/balance invariants and later RPC/guard logic. Client should prevent bad
  input and provide ergonomic feedback; server remains authoritative for writes.
- Lifecycle gates: Dart has `app_core/src/trips/trip_lifecycle.dart` and
  `trip_lifecycle_actions.dart`. Postgres has lifecycle RPCs and guards in
  `0015_trip_lifecycle.sql`, S23 lifecycle protection in
  `0027_s23_ai_theme.sql`, and per-member close notice/deemed-close behavior in
  `0029_s22_close_notice.sql`. Server RPCs are authoritative; client helpers
  should only decide presentation and whether to offer actions.
- Settlement dispute cutoff: S22 adds server behavior in
  `0029_s22_close_notice.sql`, especially
  `member_settlement_confirm_blocks_dispute` and
  `propose_expense_share_change`. Client UI can hide or explain actions, but the
  server must reject invalid changes.
- RSVP and plan state: Dart has pure RSVP models plus repository sync. The server
  guards membership and write access. Client rules should make intent clear, but
  server RLS/RPC remains the enforcement boundary.

Recommended cross-checks:

- Characterization tests for `settleUp`, net-balance construction, split
  rounding, and FX conversion before any move.
- One RLS/RPC smoke for each server-authoritative rule that the client also
  represents in UI.
- Explicit handoff line for each feature slice: "client computes preview; server
  authoritatively checks write" or the inverse, never implicit.

## 5. app_core Barrel Re-Layering

The flat `app_core.dart` barrel is the earliest high-leverage cleanup because it
can start as export reshaping rather than code movement.

Proposed sub-barrels:

- `package:app_core/design.dart` - tokens, theme extensions, reusable visual
  components, motion, spacing, radius/elevation, type scale.
- `package:app_core/domain.dart` - pure helpers and domain value objects:
  lifecycle, member roles, FX math, categories math, relative time, storage path
  naming if kept pure.
- `package:app_core/infra.dart` - Drift database, Supabase providers, sync,
  storage loading, auth repository, push registrar, analytics providers, env,
  router.
- `package:app_core/app_core.dart` - temporarily remains for compatibility, but
  new code should import the narrow barrel.

Early win:

- Make infra imports greppable.
- Let import-guard tests forbid `infra.dart` from pure/domain directories.
- Reduce accidental access to Supabase/Drift from screens that only need design
  tokens or pure helpers.

This should be an early follow-up slice, not mixed into a feature behavior
change.

## 6. Edge-Function _shared Boundary

The prompt assumed no `_shared/` directory; `main` now has one:

- `supabase/functions/_shared/fcm.ts`
- `supabase/functions/_shared/notifications.ts`

That is a useful start, but not a full edge boundary. The remaining shared shape
should include:

- `auth.ts` - verify JWT/user/service role where required.
- `cors.ts` - one CORS/header implementation.
- `json.ts` - consistent success/error response helpers.
- `provider_resilience.ts` - timeout, retry/fallback, circuit-breaker, provider
  error classification, and observability tags.
- `env.ts` - typed required/optional environment reads.

Keep the existing per-function `deno.json` hygiene rule: each function should
own its `deno.json` and frozen lockfile behavior, while importing shared helpers
via relative imports. Shared helpers should not become a hidden global runtime
with broad side effects.

First decomposition target: `resolve-theme/index.ts`. Pull provider resilience,
JSON errors, auth/client setup, and CORS first. Leave destination-theme behavior
in the function until tests or smoke coverage make behavior movement safe.

## 7. Package And Library Candidates

Ranked by value, risk, and timing:

1. `vamo_money`
   - Scope: cents, FX conversion, split validation, balances, settlement math.
   - Why first: the math is already mostly pure and money correctness is the
     highest-stakes trust surface.
   - Timing: only after characterization tests pin current behavior. Keep the
     server counterpart explicit; Postgres remains authoritative for writes.

2. `vamo_postcard`
   - Scope: place-to-visual backdrop logic across receipt, note, photo, and
     video surfaces; provider isolation for photo/map dependencies.
   - Why: already validated as a candidate in `docs/POSTCARD_SPEC.md`, and it
     can isolate a heavy provider boundary.
   - Timing: when the next capture/backdrop slice touches those files.

3. `vamo_design`
   - Scope: tokens, components, theme extensions, visual primitives.
   - Why: the design system is already shared, but adoption is not complete.
   - Timing: after S29/S28 stabilize and raw token bypasses drop. Current
     `feature_split` footprint is 151 raw `AppColors.` refs across 27 files.

4. Trip lifecycle and permissions
   - Scope: close/cancel action availability, lifecycle phases, consent display,
     read-only semantics.
   - Why: server RPCs are authoritative, but client policy needs a narrower pure
     layer for presentation and action eligibility.
   - Timing: after policy is lifted from `trip_lifecycle_actions.dart`.

5. `vamo_platform`
   - Scope: contact picker, share sheets, push registration, camera/gallery,
     storage/file adapters.
   - Why: useful only if plugin adapters keep spreading.
   - Timing: not before multiple slices need the same adapter boundary.

6. Web/admin shared provider-cost-env package
   - Scope: admin/operator dashboard environment, provider cost controls, shared
     API contracts.
   - Why: useful once the web/admin dashboard exists.
   - Timing: not before the admin surface starts.

## 8. Do Not Extract Yet

Avoid package sprawl and generic abstractions that have only one caller.

- Do not extract every screen model into a package. Prefer inline pure helpers
  until reuse or cross-language drift risk appears.
- Do not extract `vamo_design` while most downstream code still bypasses tokens
  with raw `AppColors.` usage. Fix adoption and guardrails first.
- Do not extract lifecycle policy before separating pure action eligibility from
  Riverpod/UI/RPC concerns.
- Do not create a general "repository framework" for Drift/Supabase/sync. The
  repositories need thinner policy boundaries, not a second orchestration layer.
- Do not create a web/admin shared package before the web/admin surface exists.
- Do not move edge business behavior out of `resolve-theme` until shared helper
  extraction and smoke coverage make the behavior-preserving move obvious.

## 9. Recommended Execution Strategy

Do not run a standalone big-bang refactor wave. Fold extraction into the slice
that already opens the relevant file:

- S22 close/settlement work: characterize and protect settlement math, consent
  display, and lifecycle server/client agreement before moving money or close
  policy.
- S30 capture/backdrop work: use the postcard boundary only when capture or
  visual-backdrop files are already open.
- S29/S28 design work: reduce raw `AppColors.` and `EdgeInsets` bypasses as
  touched files adopt tokens.
- Plan work: extract grouping/reorder/RSVP policy only when plan files reopen.
- Edge/provider work: split `_shared` helpers when an edge function is already
  being changed or when `resolve-theme` needs its next provider hardening pass.

Two proactive exceptions are worth doing as separate small slices:

- `app_core` barrel re-layering, because it is export reshaping with high
  greppability value.
- The import-guard test, because it is additive and gives the governance rule
  teeth.

## 10. Guardrail Import-Guard Test Recommendation

Add a CI-enforced import-guard test as the first follow-up implementation slice.
It should fail `melos run ci` when protected pure/domain directories import
Flutter widgets, Drift, Supabase, Riverpod, storage, analytics, or platform
plugins.

Recommended starting allowlist:

- Protect `packages/feature_split/lib/src/expenses/expense_split.dart`
- Protect `packages/feature_split/lib/src/settle/settle_up.dart`
- Protect `packages/feature_split/lib/src/expenses/receipt_ocr_parse.dart`
- Protect `packages/feature_split/lib/src/expenses/receipt_ocr_form_prefill.dart`
- Protect `packages/app_core/lib/src/fx/fx_math.dart`
- Protect `packages/feature_split/lib/src/plan/event_rsvp_models.dart`
- Protect `packages/app_core/lib/src/trips/trip_lifecycle.dart`
- Protect `packages/feature_split/lib/src/trips/close_report_models.dart`

Then extend the same guard to newly touched component files:

- Flag new raw `AppColors.` usage when a file is supposed to use S29 semantic
  tokens.
- Flag new ad hoc `EdgeInsets` usage where spacing tokens are available.
- Flag imports of `app_core/infra.dart` from pure/domain directories once the
  sub-barrels exist.

The guard should be directory/file allowlist based at first, not a broad static
analysis framework. Start narrow, make violations actionable, and expand it as
the boundaries settle.

## 11. Money-Refactor Safety Rule

Any move of settlement, split, balance, FX, or close-report money code must be
characterization-test-gated:

1. Add tests that pin current outputs for known inputs, including exact cents,
   debtor/creditor ordering, rounding, zero balances, settled-out/settled-in
   offsets, and mixed-currency conversion.
2. Run those tests against the current implementation.
3. Move or re-layer the code behind the pinned tests.
4. Add server smoke or fixture checks when a Dart rule mirrors RLS/RPC behavior.

Behavior preservation comes first. Cleaner structure is useful only if testers
and trip members keep seeing the same money results.
