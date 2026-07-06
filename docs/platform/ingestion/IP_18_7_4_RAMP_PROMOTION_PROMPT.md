# IP-18.7.4 — Operator-Controlled Autonomy Ramp Promotion

Implementation prompt. Agreed design (2026-07-07) after two-review reconciliation. Deliver as **two PRs**:
PR 1 = control-plane foundation, PR 2 = console UI. Do not combine.

## Context (read first)

- `docs/platform/ingestion/AUTONOMOUS_BATCH_ORCHESTRATION.md` — IP-18.7 autonomy chain (policy envelope,
  bounded executor, scheduler, ramp modes).
- `web/packages/ingestion-platform/core/src/autonomy-ramp-policy.ts` — IP-18.7.2 ramp modes + the pure
  `evaluateAutonomyRampPromotion()` that this slice finally wires to a real mutation.
- Current state: ramp mode lives in `summary.rampMode` on `ingestion_autonomy_policies` (advisory only);
  profile caps are **display warnings, not enforced**; promotion today = manual owner-run SQL. The live
  policy `vamo-eu-poi-staging-v1` is in **`staging_ramp`** — the backfill must preserve that.

## Trust model (the point of this slice)

Layers may only **narrow**, never widen, the layer above:

1. **Owner** (SQL, no app grants) provisions the policy row: absolute ceiling bounds, transitions, status.
2. **Operators** move `ramp_mode` within that ceiling: promotion requires admin + AAL2 + fresh MFA;
   demotion/pause requires an authenticated admin/operator and an audit reason, but no freshness ceremony.
3. **Agent** operates within `min(owner ceiling, ramp profile caps)` — the effective envelope.

Division of enforcement (do not blur it):

- **Database** enforces what is stable and structural: transition legality (one step up, any step down),
  optimistic concurrency, audit/event atomicity, `steady_state` locked until IP-18.6.
- **App (route + pure policy)** enforces identity and evolving semantics: admin role, AAL2 + fresh MFA
  for promotion, authenticated fail-safe demotion, active-blocker hard gate, advisory readiness evidence.
- Do **NOT** duplicate blocker/readiness semantics in SQL (drift risk). Do **NOT** treat the SQL function
  as validating identity — it records claimed actor identity; verification is the route's job.

---

## PR 1 — Foundation (control plane only, no UI)

Branch `feature/ip18.7.4-ramp-promotion` off current `origin/main`.

### 1. Schema — `web/packages/ingestion-platform/core/sql/control_schema.sql`

Add to `ingestion_platform.ingestion_autonomy_policies` (table ~line 754):

- `ramp_mode text not null default 'bootstrap'`
- `constraint ingestion_autonomy_policies_ramp_mode_check check (ramp_mode in
  ('bootstrap','staging_ramp','volume_ramp','steady_state'))`
- Idempotent backfill statement (schema file is re-applied to the live control DB):
  `update ... set ramp_mode = summary->>'rampMode' where summary->>'rampMode' in (...) and ramp_mode = 'bootstrap';`
  guarded so re-runs are no-ops. Verify in the PR body with a query plan/read-only check that the live
  policy stays `staging_ramp`.

### 2. SQL function — same file

```sql
create or replace function ingestion_platform.promote_autonomy_ramp(
  p_project_key text,
  p_policy_key text,
  p_expected_current_mode text,
  p_requested_mode text,
  p_actor_type text,
  p_actor_id text,
  p_audit_reason text
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, ingestion_platform
```

Behavior (all-or-nothing, raise exceptions with stable error codes in the message):

- Reject unknown modes; reject same-mode (`same_mode`); reject empty/whitespace `p_audit_reason`
  (`missing_audit_reason`); reject empty actor fields.
- Ladder = bootstrap < staging_ramp < volume_ramp < steady_state. **Promotion must be exactly one step
  up** (`skips_required_ramp`). **Demotion may be any number of steps down** — never gated beyond an
  authenticated caller + reason (fail-safe direction).
- **Hard-refuse any promotion to `steady_state`** (`steady_state_locked`) — remove this guard in the
  IP-18.6+ slice that makes production handoff real. This makes "skip to steady_state" impossible at the
  DB even if every app layer is bypassed.
- Lock the policy row `for update`; require `ramp_mode = p_expected_current_mode` else raise
  (`ramp_mode_conflict`) — optimistic concurrency against double-promotion.
- Update `ramp_mode` + `updated_at`; insert `ingestion_audit_log` row (action
  `promote_autonomy_ramp` / `demote_autonomy_ramp`, target_type `autonomy_policy`, target_id = policy id,
  reason, payload `{fromMode, toMode, policyKey, policyVersion}`); insert `ingestion_events` row
  (event_type `autonomy.ramp.promoted` / `.demoted`, severity `info`, signal `autonomy_ramp`) — all in the
  same transaction.
- Return `jsonb`: `{ok, policyId, fromMode, toMode, auditId}`.
- `revoke all on function ... from public;`

### 3. Bootstrap — `web/packages/ingestion-platform/core/sql/control_bootstrap_confluendo.sql`

- `grant execute on function ingestion_platform.promote_autonomy_ramp(...) to confluendo_app;`
- **No new table grants.** `confluendo_app` must still have zero direct write grants on
  `ingestion_autonomy_policies` — that stays the boundary.
- Update the IP-18.7 comment block accordingly.

### 4. Enforced effective bounds — `autonomy-executor.ts` + `autonomy-policy.ts` + `autonomy-control-read.ts`

- `autonomy-control-read.ts`: select `ramp_mode` into the policy envelope (`rampMode` becomes real, no
  longer read from `summary`). Keep `readAutonomyRampMode(summary)` only as fallback for pre-migration
  rows.
- New pure helper in `autonomy-ramp-policy.ts`:
  `applyRampProfileToEnvelope(policy) -> { effective: AutonomyPolicyEnvelope, ownerCeiling: {...}, profileCaps: {...} }`
  where effective bounds = `min(policy row value, profile value)` for `maxUnitsPerCycle`,
  `maxRowsPerCycle`, and each of `rollingLimits.{maxCyclesPerDay,maxUnitsPerDay,maxRowsPerDay}` (profile
  limits apply even when the policy row omits a rolling key; policy-only extra keys pass through).
- `autonomy-executor.ts` `loadAutonomyCycleContext`: apply the helper **once, right after
  `loadAutonomyPolicy`**, and feed the *effective* envelope to `evaluateAutonomyCycle` and everything
  downstream (single choke point — do not sprinkle mins elsewhere). Keep owner ceiling + profile caps on
  the context for read-model display.
- `buildAutonomyRunKey`: add a `ramp:<mode>` part (all decisions, not just terminal) so promotion
  refreshes the agent's idempotency space without a `policy_version` grant.

### 5. Pure promotion policy extension — `autonomy-ramp-policy.ts`

Extend `evaluateAutonomyRampPromotion` (keep it pure):

- Principal input aligned with the console auth principal shape. Promotion requires role `admin`,
  `assuranceLevel === 'aal2'`, and fresh step-up within the same freshness window the wave policy uses
  (`stale_step_up` block). Autonomous/api actors remain blocked (`actor_not_operator`).
- Demotion: any-step-down allowed and fail-safe. Require only an authenticated admin/operator identity
  plus an audit reason; do **not** require fresh step-up, AAL2, readiness evidence, or blocker clearance.
  Demotion blocks are only: unknown mode, same mode, missing reason, unauthenticated/unauthorized actor.
- New hard block for promotion: `active_critical_blockers` when the current batch queue snapshot has
  `blockerSummaries.length > 0 || progress.blocked > 0` (snapshot passed in by the route; policy stays pure).
- Promotion to `steady_state`: keep `production_handoff_not_ready` (mirrors the DB lock).
- Advisory readiness (promotion only, returned as `warnings: string[]` + `requiresAcknowledgment: true`
  on the ok result, never blocks): cycles run in current mode, failed-run count, paused-run count,
  staging-canary success count, sample-size note when cycles < a small threshold. Inputs arrive as a
  plain `readiness` object; computing it is the control-read's job, not the policy's.

### 6. Control write + readiness read — new `autonomy-ramp-control.ts` in `core/src`

- `promoteAutonomyRamp({client|connectionString, projectKey, policyKey, expectedCurrentMode,
  requestedMode, actor, auditReason})` — thin wrapper that calls the SQL function and maps DB error codes
  to typed results (no SQL logic in TS).
- `loadAutonomyRampReadiness(client, policyId)` — counts from `ingestion_autonomy_runs` since the later of
  (latest `autonomy.ramp.*` audit event for the policy, 7 days ago): advanced/completed/failed/paused,
  plus `staging_canary_succeeded` unit count from the queue snapshot. Read-only.

### 7. Tests (PR 1)

Pure: one-step up ok; skip blocked; same-mode blocked; demotion any-step ok; demotion ignores readiness;
demotion succeeds for stale/AAL1 admin sessions; missing reason blocked; viewer-role blocked;
`autonomous_agent` blocked; promotion aal1 blocked; promotion stale-step-up blocked; steady_state blocked;
active-blockers blocked; advisory warnings populated;
`applyRampProfileToEnvelope` min() per mode incl. rolling limits and missing-key cases.

DB smokes (disposable Postgres, follow `autonomy-executor.test.ts` conventions):

- Function happy path promotes staging_ramp→volume_ramp, writes audit + event rows atomically.
- `ramp_mode_conflict` on stale expected mode (simulate concurrent promotion).
- Skip bootstrap→volume_ramp refused **by the function** with app layers bypassed.
- steady_state promotion refused by the function.
- Demotion volume_ramp→bootstrap succeeds.
- **Grant boundary as executable test**: under `set role confluendo_app`, direct
  `update ingestion_autonomy_policies set ramp_mode/max_units_per_cycle/...` fails `42501`, while
  `select promote_autonomy_ramp(...)` succeeds. This is the test that matters most.
- Executor smoke: policy row bounds 100/25000 + `ramp_mode='bootstrap'` ⇒ cycle advances at most 1 unit /
  2 rows; flip to `staging_ramp` (via the function) ⇒ next cycle uses 5/100; run keys differ across modes.

### 8. Docs (PR 1)

`AUTONOMOUS_BATCH_ORCHESTRATION.md` (ramp section: enforced-bounds semantics, promotion flow, division of
enforcement), `BUILD_SLICES.md` (IP-18.7.4 entry), `bootstrap/README` note re: re-apply requirement.

---

## PR 2 — Console UI (after PR 1 merges)

### Route — `web/apps/confluendo-console/app/api/admin/ingestion/autonomy/ramp/route.ts`

Follow the `batch-canary-wave/approve/route.ts` structure, with one important split:
parse/validate body
(`{projectKey, policyKey, expectedCurrentMode, requestedMode, auditReason, acknowledgedWarnings?: string[]}`)
→ load policy to determine direction → promotion uses `authorizeStagingCanaryRequest` (fresh MFA/AAL2);
demotion uses authenticated admin/operator auth without a fresh-step-up requirement → load queue snapshot +
readiness → `evaluateAutonomyRampPromotion` (409 with blocks on refusal; 409 with `warnings` when promotion
has unacknowledged advisories) → `promoteAutonomyRamp` → 200 with `{fromMode, toMode, auditId}`. 503 when
control DSN unset. Never bypass the pure policy even though the DB re-checks transitions.

### UI — `web/apps/confluendo-console/app/admin/ingestion/`

- New client component `autonomy-ramp-control.tsx` modeled on `batch-canary-wave-approval-control.tsx`
  (existing MFA step-up + audit-reason UX).
- Extend `lib/ip18-autonomy-data.ts` + `page.tsx`: Ramp card inside the IP-18.7 panel showing current
  mode + profile label, **three columns per bound: owner ceiling / ramp cap / effective**, readiness
  evidence, existing `resolveAutonomyRamp` warnings.
- Single **"Promote to <next mode>"** button (never a free mode picker); disabled + reason shown when
  hard-blocked. Demote control = select limited to strictly lower modes.
- Confirmation modal: promotion includes MFA step-up + audit reason + **type the target mode** to confirm
  + explicit checkbox acknowledgment when advisory warnings exist. Demotion/pause includes audit reason +
  type target mode, but no fresh-MFA gate.
- Panel copy MUST state: *promotion does not widen live staging writes — autonomous wave approvals stay
  capped at 1 unit; consumer delivery waves are governed separately (IP-18.6).* (Operators will otherwise
  promote and wonder why waves didn't widen.)
- Keep the Sample/Live source labeling convention; degrade gracefully when tables/function are missing.

### Tests (PR 2)

Route: unauthenticated 401/403; viewer 403; missing reason 400; stale/AAL1 promotion blocked; stale/AAL1
demotion allowed for authenticated admin/operator; blocked promotion 409 with block codes; unacknowledged
warnings 409; happy path 200. Component-level rendering tests per existing console conventions (if any
exist for sibling controls; do not invent a new harness).

---

## Non-goals (state them in both PR descriptions)

- No widening of `FIRST_AUTONOMOUS_STAGING_WAVE_MAX_UNITS` (separate governed slice).
- No IP-18.6 production package waves; `steady_state` stays locked at the DB.
- No policy status/bounds/transitions mutation from the app — owner-only, unchanged.
- No automatic promotion; the agent may at most *recommend* via existing telemetry.

## Safety statement (required in both PRs)

Control-plane only. No provider calls, no Vamo staging/prod writes, no live canary execution. The only new
app-reachable write is `promote_autonomy_ramp()` — transition-legal, audit-atomic, concurrency-guarded,
steady_state-locked.

## Validation gates (each PR)

`npm --workspace @confluendo/ingestion-platform test` with disposable Postgres (DB smokes must RUN, not
skip), `ip15:boundary-audit`, `@confluendo/console` build, `@vamo/site` build, `git diff --check`.

## Ops checklist (PR 1 body, do after merge)

1. Apply updated `control_schema.sql` to the live control DB (adds column + function; verify backfill kept
   `vamo-eu-poi-staging-v1` at `staging_ramp`).
2. Re-run `control_bootstrap_confluendo.sql` (EXECUTE grant). This has been missed twice before — treat as
   part of the slice, not follow-up.
3. Read-only verify: `select policy_key, ramp_mode from ingestion_platform.ingestion_autonomy_policies;`
   and one preview cycle showing effective bounds.
