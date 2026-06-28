# First Vamo Staging Canary (IP-16)

Status: design spec - 2026-06-28. No execution path is implemented yet; this
document is the contract that the IP-16 code slice must satisfy.

IP-14 proved the dry-run loop end to end:

```text
Vamo contract -> Confluendo import -> scorecard -> preflight -> scout
  -> sample_dry_run -> review_required (no write of any kind)
```

IP-16 takes exactly one target that already reached `review_required` and lets
an operator promote it to a **tiny, bounded, reversible write into Vamo staging
only**. Production stays structurally impossible. This is the first time
Confluendo writes to a consumer database, so the slice is deliberately small,
heavily gated, fully audited, and trivially rollback-able.

This spec extends `TARGET_SELECTION_AND_SCHEDULING.md` §2 (tier
`staging_canary`) and §5 (stage 5, "Staging canary"). It does not replace the
selection/scheduling model; it defines the promotion that follows a clean dry
run.

## 1. Goal

Promote one reviewed dry run to a single small Vamo staging shipment:

- Input: a target at tier `sample_dry_run` whose latest `ProgressiveRunReport`
  has `reachedReview === true`, a compatible shipment diff, and `wroteToTarget
  === false`.
- Output: an `approved_write` shipment against the Vamo **staging**
  place-intelligence cache, bounded to a tiny slice, recorded in the shipment
  ledger with a reversible item set and an audit trail.
- The promotion is operator-initiated and operator-approved. Confluendo never
  promotes itself, and AI never promotes anything (advisory only, per
  `TARGET_SELECTION_AND_SCHEDULING.md` §3).

Success means: the canary rows exist in Vamo **staging**, every written row is
attributable to a `shipment_id`/`run_id`, the dashboard shows the canary as a
distinct state, and the rows can be removed or reverted with one operator
action.

## 2. Scope, Source, And Target

| Aspect | IP-16 rule |
| --- | --- |
| Source | Open/cacheable snapshot only (e.g. FSQ OS Places snapshot, GeoNames, Wikidata) imported via the IP-03.5 consumer contract. No live scraping, no provider API calls, no VPN/proxy/evasion. |
| Target | Vamo **staging** place-intelligence cache only. Resolved from consumer config, never hard-coded into platform core. |
| Write mode | A single `approved_write` shipment (see §9 mapping). One shipment, one target, one bounded slice. |
| Environment proof | The target adapter must positively confirm it is connected to a staging DSN/environment before any write; absence of proof is a hard block, not a warning. |
| Consumer coupling | Vamo enters only as imported contract/config/fixtures/credentials. Platform core gains no Vamo import. |

### Hard production block

Production is blocked at three independent layers, so a single mistake cannot
ship to production:

1. **Policy layer**: `buildScheduleProposal` already rejects
   `production_write` (`production_write_forbidden`). IP-16 must keep that and
   additionally reject any promotion whose resolved target environment is not
   `staging`.
2. **Schema layer**: `ingestion_targets.safety_mode` and
   `ingestion_shipments.mode` only allow `('dry_run', 'approved_write')`. There
   is **no `production_write` enum value at all**, so a production shipment row
   cannot be represented in the control plane. IP-16 must not widen these
   enums.
3. **Adapter layer**: the staging target adapter must refuse to execute against
   a connection it cannot prove is staging, and there is no production target
   adapter wired in this slice.

No IP-16 code may add a production environment, a production DSN, a
`production_write` enum, or a "promote to production" control.

## 3. Promotion Gate (Approval Requirement)

A canary promotion is accepted only when **all** of the following hold. These
mirror the `ApprovalRequirement` already returned by `schedule-proposal.ts` and
`progressive-run.ts` (`role: "ingestion_admin"`, `requireMfa: true`,
`requireAuditReason: true`).

| Gate | Requirement |
| --- | --- |
| Reviewed dry run | Latest run report for the target has `reachedReview === true`, `shipmentDiff.compatible === true`, and `wroteToTarget === false`. |
| Role | Authenticated principal resolves to `ingestion_admin` via the IP-11 admin allowlist (`ingestion-admin-auth`), not from caller-supplied fields. |
| MFA step-up | A fresh MFA step-up, reusing the IP-11 `reset` step-up contract (recent, not a stale session claim). |
| Audit reason | A non-empty operator reason string, recorded verbatim in `ingestion_audit_log`. |
| Explicit transition | The request explicitly promotes `review_required -> staging_write`; there is no implicit or batch promotion, and no "approve all". |
| Bounds attested | The operator confirms the canary bounds in §4; the server re-validates them and does not trust client-supplied counts. |

Machine tokens (IP-11) may run non-destructive operational commands but **must
not** promote a canary. Promotion is a destructive, human-gated action.

Every promotion attempt — accepted, rejected, or no-op — writes an
`ingestion_audit_log` row (`actor_type='operator'`, `action='promote_staging_canary'`,
`target_type='target'`, `reason=<operator reason>`).

## 4. Canary Bounds

The canary is intentionally the smallest useful write.

| Bound | Rule |
| --- | --- |
| Row count | Hard upper bound (recommended `<= 50` rows for the first canary), enforced server-side against the actual planned shipment item count, not a client claim. Exceeding the bound blocks the shipment. |
| Geography | Exactly one narrow geography (e.g. one city/region), carried in `ScheduleScope.geography`. |
| Category | Exactly one POI/category band, carried in `ScheduleScope.category`. |
| Idempotency | Every write is an idempotent upsert keyed on the target's declared `upsertKeys`; re-running the same canary is a no-op, never duplicate rows. Each `ingestion_shipment_items` row carries a stable `idempotency_key`. |
| Operations | Only `insert`/`update`/`no_op`. `delete` is not allowed in a canary shipment. `merge`-mode tables remain unsupported (already a dry-run incompatibility). |
| Single shipment | One `ingestion_shipments` row per canary. No fan-out across multiple targets. |

The bounded slice is the same slice the dry run already validated, so the canary
ships rows that have already passed policy gates, attribution checks, and a
compatible diff.

## 5. Shipment Execution Path

The write reuses the proven dry-run diff and only changes the final apply step.

```text
review_required run report (compatible diff, wroteToTarget=false)
  -> operator promote request (role + MFA step-up + reason + explicit transition)
  -> platform-core promotion policy validates gate + bounds + staging-only
  -> re-plan dry-run diff (deterministic) to confirm it still matches review
  -> open ingestion_shipments row (mode=approved_write, status=approved)
  -> target adapter proves staging connection
  -> adapter applies bounded idempotent upserts inside one transaction
  -> per-row ingestion_shipment_items recorded (applied/failed/skipped)
  -> shipment status -> succeeded | failed; checkpoint + events emitted
  -> dashboard shows staging_canary_shipped (or blocked) + rollback handle
```

Boundaries:

- **Platform core** owns: the promotion policy (gate evaluation, bounds
  enforcement, `review_required -> staging_write` legality, staging-only
  decision), the shipment/ledger planning, idempotency-key derivation, and the
  pure state transitions. All of this is dependency-free and testable without a
  DB.
- **Target adapter** owns: the only code allowed to write to Vamo staging. The
  write happens through the `adapters/target` boundary as a new
  `apply`/`staging-write` path that extends the existing dry-run planner; the
  diff is computed exactly as in `planPostgresDryRun`, then applied in a single
  transaction. No write logic leaks into core, the dashboard, or Vamo app code.
- **Consumer (Vamo)**: supplies the staging DSN/credentials (server-side only,
  never in browser code) and the contract/config that names the staging target.
  Vamo remains a consumer profile; platform core gains no Vamo dependency.

## 6. Rollback And Reversibility

Every canary must be removable or reversible by an operator without manual SQL.

- **Traceability**: each written row is attributable to its `shipment_id` and
  `run_id`. `ingestion_shipment_items` already stores `shipment_id`,
  `record_key`, `idempotency_key`, `operation`, `checksum`, and `payload`; for
  `update` operations the prior row state (or its `previousChecksum`) is
  captured so the change can be reverted, not just deleted.
- **Removal of inserts**: rows the canary inserted can be deleted by
  `(target_table, record_key)` scoped to the shipment, because inserts are
  uniquely tied to this shipment's idempotency keys.
- **Reversal of updates**: rows the canary updated can be restored from the
  captured prior state. If prior state is unavailable for any item, that item is
  classified non-reversible and the canary is flagged for manual review instead
  of silently leaving an irreversible change.
- **One operator action**: rollback is a single audited operator command
  (`action='rollback_staging_canary'`, MFA + reason), not a manual cleanup.
  Rollback is itself recorded as a shipment-scoped action with its own audit
  row.
- **Idempotent rollback**: re-running rollback after it has completed is a
  no-op.

## 7. Telemetry

The canary must be observable end to end from the dashboard without reading
logs. It reuses the existing control tables.

| Signal | Source table | What it shows |
| --- | --- | --- |
| Shipment ledger | `ingestion_shipments` + `ingestion_shipment_items` | One shipment with per-row `insert`/`update`/`no_op` operations, status, idempotency keys, checksums. |
| Checkpoint | `ingestion_checkpoints` | Durable cursor/resume point for the bounded slice. |
| Dead letters | `ingestion_dead_letters` | Rows rejected during the canary with classified reason codes. |
| Policy blocks | `ingestion_policy_evaluations` (`decision='deny'`/`'review'`) | License/retention/attribution/live-only blocks surfaced before any write. |
| Attribution | shipment item payload + `ingestion_policy_evaluations` | Required source attribution is present on shipped rows (enforced by the existing `attribution_present` quality gate). |
| Events | `ingestion_events` | Stage/signal stream: `staging_canary_approved`, `staging_canary_shipped`, `staging_canary_blocked`, `staging_canary_rolled_back`. |
| Audit | `ingestion_audit_log` | Every promote/rollback attempt with actor, reason, applied/rejected outcome. |

The dashboard read model (extending `progressive-read-model.ts`) must surface,
for the canary: shipped/updated/no-op counts, the `shipment_id`/`run_id`, the
attribution status, policy blocks, dead letters, the rollback handle, and the
dry-run invariant history (that it reached review with no write before the
canary).

## 8. Operator Dashboard State Transitions

The canary is a distinct, visible lifecycle layered on top of the IP-14
progressive states. Mutation controls stay gated by IP-11 auth.

```text
review_required
   | (operator: promote, role=ingestion_admin + MFA step-up + audit reason)
   v
staging_canary_pending      -- gate + bounds + staging-only validated, shipment opened
   | (adapter proves staging, applies bounded idempotent upsert in one txn)
   +--> staging_canary_shipped        -- success; rollback handle available
   |
   +--> staging_canary_blocked        -- gate failed, bounds exceeded, not staging,
                                          diff drifted, or write failed (no partial silent state)
staging_canary_shipped
   | (operator: rollback, MFA + audit reason)
   v
staging_canary_rolled_back  -- inserts removed / updates reverted; idempotent
```

Transition rules:

- `review_required -> staging_canary_pending` requires the full §3 gate. Any
  missing gate keeps the target at `review_required` and records a rejected
  audit row.
- `staging_canary_pending -> staging_canary_blocked` if the re-planned diff no
  longer matches the reviewed diff, bounds are exceeded, the connection is not
  proven staging, or the transaction fails. A blocked canary writes nothing
  (transaction rolled back) and offers a resolve-blockers approval, never a
  promotion path.
- Only `staging_canary_shipped` exposes a rollback control.
- `staging_canary_rolled_back -> review_required` (or `sample_dry_run`) is
  allowed so a clean re-attempt can follow after fixes.
- No transition anywhere in the graph leads to a production state; there is no
  production node.

The dashboard must still answer the six standing questions from
`TARGET_SELECTION_AND_SCHEDULING.md` §6, plus: "Did anything get written, and
can I undo it right now?"

## 9. Safety-Mode Mapping And Schema Implications

There is an intentional terminology bridge between the policy layer and the
durable control plane:

- Policy/proposal layer (`SafetyMode`): `dry_run | staging_write |
  production_write`.
- Durable layer (`ingestion_targets.safety_mode`, `ingestion_shipments.mode`):
  `dry_run | approved_write`.

IP-16 maps a policy-level `staging_write` promotion to an `approved_write`
shipment against a target whose resolved environment is `staging`. The mapping
must be explicit and one-directional:

- `staging_write` (policy) + environment `staging` -> `approved_write`
  (shipment). Allowed.
- `production_write` (policy) -> has **no** durable representation. Rejected at
  the policy layer and unrepresentable at the schema layer.

Open modeling decision for the IP-16 code slice (do not pre-empt here): whether
to record the resolved environment (`staging`) on the shipment/target row
explicitly (e.g. a dedicated `environment` column or metadata field) so the
"staging-only" guarantee is queryable, rather than implied by the absence of a
production enum. The implementation slice must choose and justify this; the
default recommendation is to store the environment explicitly in target/shipment
metadata so audits can prove staging without external context.

## 10. Explicit Stop Conditions

The canary stops (and writes nothing further) when any condition trips. These
extend `StopConditions` in `schedule-proposal.ts`.

- Safety mode is anything other than the mapped `staging_write`/`approved_write`
  staging path. (`production_write` and unknown modes hard-fail.)
- Resolved target environment is not provably `staging`.
- The reviewed run is missing, stale, not `reachedReview`, or its diff is not
  `compatible`.
- The re-planned diff drifts from the reviewed diff (schema/keys/op-count
  mismatch).
- Planned shipment item count exceeds the canary row bound, or scope is wider
  than one geography + one category.
- Any `delete` operation is present.
- Approval gate incomplete: missing role, missing/stale MFA step-up, or missing
  audit reason.
- Policy block rate, dead-letter rate, or collision rate exceeds the proposal's
  declared thresholds.
- Target schema/upsert-key incompatibility (any `ShipmentPlanIncompatibility`).
- Target write failure mid-transaction: the transaction rolls back and the
  shipment is marked `failed`; no partial canary is left behind.
- Operator pause/cancel.
- Any item is classified non-reversible before apply (canary blocked for manual
  review rather than shipping an irreversible change).

A tripped stop condition always leaves the system in a no-write or
fully-rolled-back state, emits an event, and records the reason.

## 11. Architecture Decision

Architecture decision: **pure approval/shipment policy in platform core; target
writes only through the adapter boundary; Vamo stays a consumer.**

- Platform core (`core/src/*`) owns the promotion gate, bounds enforcement,
  `review_required -> staging_write` legality, staging-only decision, shipment
  ledger planning, idempotency-key derivation, rollback planning, and the pure
  state machine. These are dependency-free, deterministic, and unit-testable
  without a database or network.
- The **only** code permitted to write to Vamo staging is the
  `adapters/target` boundary, extending the existing dry-run planner with a
  transactional, idempotent apply step that first proves a staging connection.
  No write logic lives in core, the dashboard, the Next API route, or Vamo app
  code.
- The Next API route (extending IP-11) resolves the authenticated admin
  principal and MFA step-up, then calls platform-core promotion policy and the
  adapter; the browser never holds DSNs, service-role keys, or write
  credentials.
- Vamo remains **customer zero / consumer only**: it contributes the staging
  DSN/credentials and the imported contract/config/fixtures. Confluendo platform
  core gains no import of Vamo app code, Flutter packages, Vamo web routes, Vamo
  edge functions, or Vamo migrations. Confluendo may carry Vamo only as an
  imported consumer fixture with pinned provenance.

This keeps the first real write small, reversible, fully audited, staging-only,
and on the correct side of the platform/consumer boundary, so IP-15's repo split
remains clean.
