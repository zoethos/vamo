# Autonomous Batch Orchestration

Status: roadmap guardrail — updated 2026-07-06.

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

## Commissioning vs Steady State

| Mode | Purpose | Operator involvement |
| --- | --- | --- |
| Commissioning | Prove a new source/target/write path and establish first safe bounds. | Explicit approvals, small live waves, SQL/read-model verification. |
| Governed autonomy | Run recurring eligible work inside already-approved bounds. | Review dashboards and intervene only on blockers, drift, threshold breaches, or policy changes. |
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

The next autonomy slice should be control-plane first:

- Store an `autonomy_policy` for a source/target pair.
- Store an `autonomy_run` ledger with selected units, bounds, current phase, and
  stop reason.
- Implement a dry-run-only or staging-only planner/executor loop that selects the
  next eligible units and stops before any unapproved widening.
- Keep production inbox delivery behind IP-18.6 until the staging loop has green
  evidence at the configured bound.

The first autonomous implementation should still be conservative, but the
operator interaction changes from "approve each wave" to "approve policy bounds
and respond to exceptions."
