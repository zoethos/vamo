# Target Selection And Progressive Scheduling

Status: planning spec - 2026-06-28.

Confluendo must not start ingesting because a source is available. It should
start because a target is valuable, legal to cache, operationally safe, and
observable end to end. AI can help rank and schedule work, but the policy
engine and operator approval remain the authority.

## 1. Selection Criteria

Every ingestion target gets a scorecard before it can move from proposed to
scheduled.

| Criterion | Question | Hard gate |
| --- | --- | --- |
| Consumer value | Does this target unlock a user-visible product capability or reduce paid/live calls? | A consumer owner names the use case. |
| Source rights | Can the source data be stored, retained, attributed, and shipped? | Policy engine passes license, retention, and attribution checks. |
| Target readiness | Does the target DB schema, RLS posture, upsert key, and staging environment exist? | Dry-run target compatibility passes. |
| Data quality | Are identifiers, coordinates, names, categories, and freshness good enough? | Required fields and quality gates pass on a sample. |
| Checkpointability | Can the source resume from a durable cursor after a crash? | Cursor strategy is declared and tested. |
| Cost and quota | Is the row volume, API quota, egress, compute, and operator time acceptable? | Budget and stop conditions are declared. |
| Collision risk | Could rows merge into existing canonicals incorrectly? | Collision policy exists: auto, review, or block. |
| Blast radius | Can the run be limited by geography, category, row count, or environment? | First shipment is staging-only and bounded. |
| Observability | Can the dashboard explain status, blockers, progress, and next action? | Events, checkpoints, dead letters, and stats are available. |

For Vamo place intelligence, the first targets should favor open, durable,
low-cost, high-value datasets with stable source identifiers and strong
attribution. Examples: FSQ OS Places snapshots, GeoNames, Wikidata/Wikimedia,
or consumer-owned observations. Live-only providers can enrich validation or
visuals, but they do not become durable cache sources unless policy explicitly
permits it.

## 2. Target Tiers

Targets should be promoted through tiers, not enabled all at once.

| Tier | Meaning | Example action |
| --- | --- | --- |
| `candidate` | Valuable but not proven. | AI/operator proposes it with rationale. |
| `scout` | Metadata and sample only. | Validate source format, license, and schema mapping. |
| `sample_dry_run` | Small bounded run. | Process 100-1000 rows, no target writes. |
| `staging_canary` | Small approved staging shipment. | Write one region/category slice to staging. |
| `staging_expand` | Larger bounded staging shipment. | Expand by geography, category, or source partition. |
| `production_candidate` | Ready for human production review. | Compare checksums, dead letters, collisions, and policy stats. |
| `production_approved` | Allowed to ship to production under limits. | Idempotent shipment with rollback/replay ledger. |

The default for a new target is `sample_dry_run` or lower. Production is never
the default.

## 3. AI Role

AI should be a planner and analyst, not an unbounded worker.

Allowed AI work:

- Read target specs, source metadata, prior run telemetry, and dashboard stats.
- Propose target priority with a human-readable rationale.
- Suggest source partitions such as country, category, bounding box, or row
  ranges.
- Recommend batch size, checkpoint interval, and run window from past failures
  and quota history.
- Classify dead letters and propose mapping fixes.
- Propose collision-review queues and likely duplicate clusters.
- Summarize what changed between dry-run packages.

Not allowed:

- Bypass source policy, rate limits, or terms.
- Promote AI output as a trusted durable fact without a declared policy path.
- Start production shipment without an operator approval gate.
- Hide uncertainty. Every AI recommendation needs confidence and evidence.
- Rewrite target schema or RLS rules without a migration review.

This does not prohibit an autonomous Confluendo agent from executing
already-approved policy. The distinction is authority: AI may analyze and
recommend, while an `autonomous_agent` may act only when deterministic control
state, stored policy, approval bounds, and ledger evidence already authorize the
transition.

## 4. Scheduling Model

The scheduler should create explicit work proposals before tasks are started.

```text
Target candidate
  -> AI/operator scorecard
  -> policy and schema preflight
  -> bounded schedule proposal
  -> operator approval
  -> task creation
  -> worker leases and checkpoints
  -> dashboard progress and events
  -> dry-run or staging shipment report
```

A schedule proposal should include:

- `project_key`: consumer project, for example `vamo`.
- `target_id`: platform target identifier.
- `source_id`: source registry identifier and dataset version.
- `tier`: current progression tier.
- `scope`: geography, category, source partition, row limit, or bounding box.
- `batch_size` and `checkpoint_every_rows`.
- `quota_budget`: max rows, max calls, max runtime, and max failures.
- `run_window`: earliest start, latest stop, and quiet hours.
- `stop_conditions`: policy block rate, dead-letter rate, collision rate,
  schema mismatch, target write failure, or operator pause.
- `safety_mode`: `dry_run`, `staging_write`, or `production_write`.
- `ai_rationale`: why this target is next and what evidence was used.
- `approval`: required role, MFA state, and audit reason.

## 5. Progressive Run Stages

The first real Vamo ingestion should move through these stages:

1. **Preflight**: validate YAML, source rights, target schema, RLS posture,
   attribution, and upsert keys.
2. **Scout**: read source metadata and a tiny sample, then stop.
3. **Sample dry run**: process a small bounded slice and produce a shipment diff.
4. **Review**: inspect dead letters, policy blocks, duplicates, and expected
   target changes.
5. **Staging canary**: ship a tiny approved package to Vamo staging only.
6. **Staging expand**: expand by one safe dimension such as country or category.
7. **Production review**: compare staging results, checksums, and user value.
8. **Production shipment**: ship only after explicit approval and rollback plan.

## 6. Dashboard Requirements

The operator dashboard should make ongoing work visible without opening logs.

Required views:

- **Target backlog**: proposed, scored, scheduled, running, blocked, complete.
- **AI recommendations**: target score, rationale, confidence, evidence, and
  required approval.
- **Run timeline**: current tier, stage, started by, run window, and stop
  conditions.
- **Progress**: rows read, staged, promoted, shipped, skipped, and dead-lettered.
- **Policy panel**: license, attribution, retention, media policy, live-only
  blocks, and review-required rows.
- **Checkpoint panel**: last durable cursor, worker lease, heartbeat, and resume
  point.
- **Cost and quota**: calls used, rows processed, runtime, estimated remaining,
  and circuit-breaker status.
- **Collision and quality**: duplicate clusters, confidence distribution,
  missing fields, coordinate failures, and category mapping failures.
- **Shipment diff**: insert, update, no-op, delete, checksums, and target schema
  compatibility.
- **Operator actions**: start, pause, shutdown, reset, approve next tier, replay
  dead letters, and export audit report.

The dashboard should always answer:

1. What is running?
2. Why is it running?
3. What is the next durable checkpoint?
4. What would happen if we stop now?
5. What policy or quality gates are blocking progress?
6. What operator approval is needed to move to the next tier?

## 7. First Vamo Target Recommendation

Start with one bounded, open, cacheable place source and one narrow target scope.

Recommended initial shape:

```text
consumer: vamo
domain: place_intelligence
source: FSQ OS Places snapshot or equivalent open snapshot
scope: one geography + one POI/category band
safety_mode: dry_run
target: Vamo staging place-intelligence cache
approval: admin with MFA, audit reason required before staging write
```

This gives Confluendo a visible value loop without touching production:

```text
open source rows -> policy gates -> normalized candidates -> dry-run diff
  -> dashboard review -> tiny staging canary -> expand only if clean
```

## 8. Architecture Decision

Architecture decision: pure planning policy plus adapter-backed execution.
Target scoring and scheduling rules should live in platform core as pure,
testable policy. Source reads, target writes, AI calls, and dashboard mutation
remain adapter or API boundaries.
