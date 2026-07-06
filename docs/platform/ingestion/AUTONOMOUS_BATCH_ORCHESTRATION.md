# Autonomous Batch Orchestration

Status: **IP-18.7.2 ramp modes implemented** - control-plane policy vocabulary
and read model only (2026-07-06).

Confluendo's steady-state product is **not** an operator manually approving and
executing every wave. Manual approvals and command-line execution are
commissioning tools used to prove a new source/target pair, a new write path, or
a wider blast radius.

The desired operating model is:

1. An operator defines approved data sources, target consumers, geographies,
   categories, bounds, and promotion policy.
2. Confluendo expands that policy into deterministic batch work.
3. Confluendo advances eligible work autonomously through dry-run, staging
   canary, and production-inbox delivery while staying inside the approved
   bounds.
4. Confluendo pauses only when a guard trips or a policy widening requires a new
   operator decision.

In this document, **operator** can mean either:

- a human administrator approving or changing policy, or
- an agentic Confluendo service acting under an already-approved policy.

The agent is not a bypass around policy. It is the normal steady-state operator
for monitoring, diagnosis, retry, and bounded corrective action. Human approval
is still required for new sources, new target environments, production-policy
widening, destructive actions, or any action outside stored bounds.

AI/LLM output remains advisory. The autonomous agent may use reasoning to
diagnose telemetry and propose corrective actions, but it must not decide new
sources, new target scopes, target environments, or write bounds outside stored
policy. Every executable decision must reduce to deterministic policy state,
ledger evidence, and approved bounds.

## Commissioning vs Steady State

| Mode | Purpose | Operator involvement |
| --- | --- | --- |
| Commissioning | Prove a new source/target/write path and establish first safe bounds. | Explicit approvals, small live waves, SQL/read-model verification. |
| Governed autonomy | Run recurring eligible work inside already-approved bounds. | Agent monitors and advances work; human reviews dashboards and intervenes only on blockers, drift, threshold breaches, or policy changes. |
| Policy widening | Increase geography/category coverage, max units, max rows, or delivery environment. | Fresh approval with audit reason and new bounds. |

Manual one-unit waves are valid only in commissioning. They are not the final
workflow and should not become the product's day-to-day operating model.

## Autonomy Contract

An autonomous run may proceed only when all of these are true:

- Source, consumer project, target key, target environment, and category/geography
  coverage are explicitly approved in the control plane.
- The source policy allows storage of the required facts/content.
- Dry-run reports are fresh enough for the configured source/target pair.
- The target environment was not inferred from a target key string.
- Prior commissioning evidence for the source/target/write path is green.
- Per-run and rolling bounds are available:
  - max units per run
  - max target rows per run
  - daily/weekly target-row limits
  - max blocker/error rate
  - max production-inbox packages per window
- The executor can prove the target safety guard before every consumer write
  (`confluendo_guard.environment_sentinel` for Vamo staging; production inbox
  safety checks for Vamo production).
- The ledger can make every step idempotent and auditable.

The first implementation should name those control-plane objects explicitly:

| Object | Purpose |
| --- | --- |
| `ingestion_autonomy_policies` | Human-approved envelope for a source/target pair: allowed tiers, environments, transitions, row/unit bounds, rolling limits, guard thresholds, and production-inbox handoff policy. |
| `ingestion_autonomy_runs` | Append-only cycle ledger: selected units, phase, highest safety mode, scanned/advanced counts, guard outcome, pause reason, telemetry links, corrective actions, and actor. |

These tables live in the Confluendo control DB only. They do not grant consumer
target access by themselves; target writes still go through the existing staging
canary and production inbox adapters.

## Agent Operator Responsibilities

The autonomous agent should be able to:

- continuously evaluate the queue and select the next eligible units;
- run dry-run execution inside configured bounds;
- compare live diffs against reviewed dry-run reports before staging writes;
- execute staging canaries and production-inbox packages only through the
  approved adapters;
- retry idempotent transient failures within retry policy;
- pause work when stop conditions are met;
- attach diagnosis to blockers and failed runs;
- propose corrective actions when human approval is required; and
- apply corrective actions automatically only when the action is explicitly
  allowed by policy and has a reversible/idempotent implementation.

Corrective actions that may be agent-applied inside policy include:

- retrying a failed read or target-proof check after backoff;
- refreshing a dry-run report when source and target contracts are unchanged;
- skipping already-succeeded/idempotent units;
- narrowing a run to exclude blocked units;
- pausing a source/target pair after threshold breach; and
- opening a human-review task with the exact evidence needed to decide.

Corrective actions that require human approval include:

- widening max units, max rows, geography/category scope, or rolling limits;
- changing source/provider policy;
- changing target environment;
- running production inbox delivery before the configured staging evidence is
  green;
- destructive rollback/delete operations; and
- overriding a drift, target-proof, or policy failure.

## Agent Actor Model

Implementation should extend the platform command/audit actor model with an
`autonomous_agent` actor type. The agent's authority is the intersection of:

1. one active `ingestion_autonomy_policies` row;
2. the standing platform gates for the current phase;
3. existing source/target contracts and policy checks;
4. any still-valid human approval required by that policy; and
5. idempotent ledger state showing the action has not already succeeded.

The agent must have fewer rights than a broad machine token. It may execute only
the transitions the active policy permits, against the named source/target pair,
inside the configured bounds. It cannot approve its own policy, widen its own
bounds, change source terms, change target environment, bypass MFA-required
approval, or override stop conditions.

## Telemetry Contract

The platform must emit enough telemetry for the agent to trace failures without
guesswork. Each run, unit, shipment, package, and blocker should have stable
identifiers and linkable evidence:

- policy id and version;
- autonomy run id;
- project id/key, source key, target key, and explicit target environment;
- unit key, run order, geography, category, and candidate/source row ids;
- dry-run report id, checksum, target-row counts, and `wroteToTarget`;
- expected diff and observed live diff;
- wave/package key, approval id if any, execution audit id, and shipment id;
- adapter name/version and target proof result;
- blocker code, blocker payload, first-seen timestamp, and retry count;
- exact stop condition and recommended next action;
- corrective action id, actor (`agent` or human principal), and outcome; and
- correlation ids across control DB, staging target, production inbox, and
  provider/source snapshot.

Telemetry must be structured enough for dashboards, automated monitors, and
agent diagnosis. Free-text logs are useful context, but they are not the source
of truth for corrective action.

Use existing telemetry tables where possible:

- `ingestion_events` for structured lifecycle events such as
  `autonomy.cycle.started`, `autonomy.cycle.advanced`,
  `autonomy.cycle.paused`, `autonomy.cycle.completed`, and
  `autonomy.action.applied`;
- `ingestion_audit_log` for human approvals, policy changes, agent cycle
  executions, pauses, resumes, and corrective actions; and
- `ingestion_autonomy_runs` as the first-class cycle spine joining queue units,
  dry-run reports, staging waves, production packages, blockers, and audit rows.

## Stop Conditions

The autonomous orchestrator must pause and require operator review when:

- A live diff drifts from the reviewed dry-run report.
- A new blocker code appears.
- The blocker/error rate breaches the configured threshold.
- A per-run or rolling write bound would be exceeded.
- Target proof is missing or mismatched.
- Required grants/roles are missing.
- A production inbox package is delivered but not applied within the configured
  consumer SLA.
- A source policy, contract, or imported snapshot changes.

When a stop condition is triggered, the agent should record the stop reason,
attach the evidence listed in the telemetry contract, mark the affected units or
source/target pair paused, and recommend the smallest safe corrective action.

## Relationship To Existing IPs

- IP-10.1 supplies real bounded EU POI candidates.
- IP-18.0–18.4 plan, persist, schedule, and dry-run batch units.
- IP-18.5 proves staging writes via the IP-16 adapter and establishes initial
  commissioning evidence.
- IP-18.6 packages staging-proven units for the production inbox using the IP-17
  delivery boundary.
- IP-18.7 should implement the autonomous orchestrator that advances work across
  those proven boundaries inside stored policy, instead of relying on an
  operator to monitor every wave.

## First Autonomy Slice

**IP-18.7.0 (implemented — foundation only)** landed the control-plane objects
and pure policy seam. It does **not** execute live cycles, provider calls,
staging writes, or production inbox delivery.

Implemented in IP-18.7.0:

- `ingestion_autonomy_policies` and `ingestion_autonomy_runs` in
  `control_schema.sql`, `CONTROL_TABLES` (25 tables), and Confluendo bootstrap
  grants (`SELECT` on policies; `INSERT`/`UPDATE` on runs; no `DELETE`).
- `CommandActorType` / audit `actor_type` extended with `autonomous_agent`.
  Authority is limited to an active policy envelope, existing guards, still-valid
  human approvals when required, and idempotent ledger state — not a broad
  machine token.
- Pure `autonomy-policy.ts::evaluateAutonomyCycle()` — DB-free, deterministic,
  reusing batch dry-run and staging-canary policy concepts.
- `autonomy-read-model.ts` + `autonomy-control-read.ts` and a read-only
  `/admin/ingestion` panel (Sample / Live control plane labels).
- Reserved telemetry contract: `autonomy.cycle.started`, `autonomy.cycle.advanced`,
  `autonomy.cycle.paused`, `autonomy.cycle.completed`, `autonomy.action.applied`.

Still deferred after IP-18.7.0:

- ~~Live executor loop that appends `ingestion_autonomy_runs` cycles and performs
  bounded dry-run / staging actions.~~ **Implemented in IP-18.7.1 (control-plane only).**
- Production inbox phase execution (requires IP-18.6 package-wave support).
- Autonomous corrective actions beyond pause/recommend.
- Live staging-canary **execution** (human confirmation-gated runbook remains required).

## IP-18.7.1 — Bounded Executor (implemented)

**IP-18.7.1** adds `autonomy-executor.ts` and `npm run ip18:autonomy-cycle`:

- Evaluates the active policy, records one `ingestion_autonomy_runs` cycle per
  invocation, and performs **at most one** bounded control-plane action:
  - `schedule_dry_run` via `scheduleBatchDryRun`
  - `execute_dry_run` via `executeBatchDryRun` (fixture simulation only)
  - `approve_staging_wave` via `approveBatchStagingCanaryWave` (control-plane approval only)
- Emits `autonomy.cycle.*` and `autonomy.action.applied` rows in
  `ingestion_events`.
- Preview by default; execute requires `--execute` and
  `CONFIRM_CONFLUENDO_AUTONOMY_CYCLE=YES`.
- **Does not** call `executeBatchStagingCanaryWave`, providers, Vamo staging DSNs,
  or production inbox delivery. Production inbox remains `waiting_for_ip18_6`.

Human operators approve policy bounds once; they respond to exceptions instead of
approving every wave in steady state. Live staging writes still require the
existing human confirmation-gated runbook.

## IP-18.7.2 - Autonomy Ramp Modes (implemented)

The first live policy intentionally used `2 units/day` because it was a
bootstrap proof of the autonomous executor, audit actor, telemetry, and
fail-closed behavior. That limit is not the product's steady-state ingestion
model.

IP-18.7.2 names the operating ramp explicitly:

| Ramp mode | Purpose | Profile |
| --- | --- | --- |
| `bootstrap` | Commissioning proof for a new source/target/write path. | 1 unit/cycle, 2 rows/cycle, 2 units/day. |
| `staging_ramp` | Controlled staging expansion after bootstrap evidence is green. | 5 units/cycle, 100 rows/cycle, 25 units/day. |
| `volume_ramp` | Higher-volume staging and production-prep mode. | 25 units/cycle, 5,000 rows/cycle, 250 units/day. |
| `steady_state` | Production-scale autonomous operation after IP-18.6 package waves and apply telemetry. | 100 units/cycle, 25,000 rows/cycle, 1,000 units/day. |

The ramp mode is stored as control-plane policy metadata, for example
`summary.ramp.mode = "bootstrap"`, and `/admin/ingestion` surfaces both the
active mode and profile warnings when a stored policy exceeds its declared
profile.

Ramp widening is deliberately a human/operator decision:

- only an admin operator may promote the ramp;
- the autonomous agent cannot widen its own policy;
- promotions advance one step at a time (`bootstrap` -> `staging_ramp` ->
  `volume_ramp` -> `steady_state`);
- `steady_state` is blocked until production inbox package waves and apply
  telemetry are implemented; and
- this slice does not mutate the live control DB.

Live policy widening remains an owner/operator SQL step with audit evidence.
After widening, the autonomy executor can continue advancing work inside the new
stored bounds.

### Ops note — live control DB

Live dashboard autonomy rows require applying the updated
`control_schema.sql` and `control_bootstrap_confluendo.sql` to the Confluendo
control DB when schema or grant files change. IP-18.7.2 has no schema change;
it reads existing policy metadata and degrades to `bootstrap` for legacy rows.

The next autonomy slice after IP-18.7.2:

- IP-18.6 production inbox package waves, then autonomous production-inbox phases.
- Optional scheduled/cron invocation of `ip18:autonomy-cycle` with monitoring.
- Autonomous corrective actions beyond pause/recommend when explicitly allowed by policy.

The steady-state operator interaction changes from "approve each wave" to
"approve policy bounds and respond to exceptions."
