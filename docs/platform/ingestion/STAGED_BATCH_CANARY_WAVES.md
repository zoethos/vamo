# Staged Batch Canary Waves (IP-18.5)

Status: **IP-18.5.2 execution implemented; first refreshed live wave succeeded**
— 2026-07-03. Wave approval (IP-18.5.1) and confirmation-gated per-unit
execution (IP-18.5.2) are in code; live Vamo staging execution remains
operator-gated and is not run in CI.

IP-18.4 proved bounded fixture-only dry-run execution against the Confluendo
control plane. IP-18.5 is the first batch slice that may touch a consumer
database again. **Production is forbidden in IP-18.5.** All Vamo staging writes
must reuse the existing IP-16 staging-canary adapter (`applyPostgresStagingCanary`);
this slice must not introduce a second staging write path.

## 1. Core design decision

A **staging canary wave** is a bounded sequence of **independent per-unit IP-16
staging canaries**. There is no aggregate multi-unit direct write path.

| Property | Rule |
| --- | --- |
| Write boundary | Each unit calls `applyPostgresStagingCanary` exactly once per successful attempt. |
| Sentinel proof | Each unit proves Vamo staging via `confluendo_guard.environment_sentinel` before any write. |
| Atomicity | Each unit is one transactional shipment; failure rolls back that unit only. |
| Ledger | Each unit gets its own `ingestion_shipments` / `ingestion_shipment_items` rows and links back to the wave item. |
| Idempotency | Each unit uses declared upsert keys and a stable per-unit shipment key; replay is a no-op. |
| Rollback | Each unit is individually rollback-able via the existing IP-16 rollback path. |
| Orchestration | IP-18.5 coordinates eligibility, approval, ordering, stop-on-failure, and control-plane state only. |

```text
dry_run_succeeded queue unit
  -> IP-18.5 wave eligibility + ramp policy
  -> operator approval (control DB only)
  -> per unit: build ProgressiveRunReport-shaped input from dry-run report
  -> per unit: evaluateStagingCanaryPromotion()  [reuse IP-16 pure policy]
  -> per unit: applyPostgresStagingCanary()      [reuse IP-16 adapter — only write path]
  -> per unit: record shipment ledger + wave item result
  -> stop wave on first unit failure (see §6)
```

IP-18.5 is a **batch orchestration layer over IP-16 canaries**. It must not
introduce a parallel staging approval/write model, duplicate promotion policy,
or a bulk upsert that bypasses the adapter.

Related specs:

- `STAGING_CANARY.md` — single-target IP-16 contract (authoritative for adapter behavior)
- `BATCH_TARGET_PLANNING.md` — batch queue context (IP-18.0–18.4)
- `BUILD_SLICES.md` — slice phasing and acceptance

## 2. Live baseline and first-wave evidence

### 2.1 Initial IP-18.4 baseline

| Signal | Value |
| --- | --- |
| Scheduling audit id | **15** — 36 units `ready_for_dry_run` → `dry_run_ready`, environment **staging** |
| Execution key | `batch-dry-run:vamo-eu-poi-sample:audit:15` |
| Execution id | **1** — status `succeeded`; execution audit row **16** |
| Queue after first bounded dry run | **3** `dry_run_succeeded`, **33** `dry_run_ready` |
| Succeeded units | `vamo-place-intelligence:rome-italy:poi`, `vamo-place-intelligence:paris-france:landmark`, `vamo-place-intelligence:barcelona-spain:landmark` |
| Dry-run invariant | All three reports show `wroteToTarget=false` |

IP-18.5 waves start from `dry_run_succeeded` units only. The first live staging
wave is hard-capped to **1 unit** from the three succeeded units, not from the
33 still-`dry_run_ready` rows.

### 2.2 Refreshed IP-10.1/IP-18.5 evidence

IP-10.1 replaced the 5-row demo fixture with a bounded EU POI snapshot. After
PR #135 fixed dry-run target-row counting, the operator helper re-ran IP-18.4
against the next two wave candidates:

| Signal | Value |
| --- | --- |
| IP-18.4 execution id | **4** |
| IP-18.4 execution audit id | **33** |
| Refreshed dry-run units | `vamo-place-intelligence:paris-france:landmark`, `vamo-place-intelligence:barcelona-spain:landmark` |
| Dry-run invariant | Both reports show `insert_count=2`, `wroteToTarget=false`, and no blockers |
| Wave approval | Dashboard approval audit id **34**, max units **1**, max rows **2** |
| Wave execution | Status **succeeded**, execution audit id **36**, shipment id **4** |
| Succeeded wave unit | `vamo-place-intelligence:paris-france:landmark` |

Vamo staging verification for the succeeded unit returned the joined canonical
and source-ref row:

```sql
select
  r.provider,
  r.source_place_id,
  r.canonical_id,
  c.canonical_key,
  c.display_name,
  c.feature_type,
  c.latitude,
  c.longitude,
  r.created_at as source_ref_created_at,
  c.created_at as canonical_created_at
from public.location_source_refs r
join public.location_canonicals c on c.id = r.canonical_id
where r.provider = 'fsq_os_places'
  and r.source_place_id = 'fsq_paris_louvre_landmark';
```

Expected/current evidence:

| Field | Value |
| --- | --- |
| `canonical_id` | `0b9523e6-07bd-510a-ba3e-d22dfdbecf9a` |
| `canonical_key` | `fsq-paris-louvre-landmark` |
| `display_name` | `Louvre Pyramid` |
| `feature_type` | `landmark` |
| Coordinates | `48.8606`, `2.3376` |
| Created at | `2026-07-03 23:03:21.699871+00` |

This is the first successful IP-18.5 live staging wave over refreshed IP-10.1
supply. It wrote only to Vamo staging via the IP-16 adapter, did not write to
Vamo production, and did not call a live provider. Continue the ramp with the
already-`dry_run_succeeded` Barcelona landmark unit before widening beyond one
unit per wave.

## 3. State machine

### 3.1 Queue item statuses (IP-18.5 extension)

IP-18.5 extends `ingestion_batch_queue_items.status` with staging-canary lifecycle
states. **No production state exists in IP-18.5.**

```text
dry_run_succeeded
   | (operator: mark wave-eligible / auto-eligible when gates pass)
   v
staging_canary_ready
   | (operator: approve wave, admin + AAL2 + fresh MFA + audit reason)
   v
staging_canary_approved
   | (wave executor: begin unit)
   v
staging_canary_running
   | (per unit: applyPostgresStagingCanary)
   +--> staging_canary_succeeded
   |
   +--> staging_canary_blocked
```

Rules:

- **`dry_run_succeeded` → `staging_canary_ready`**: pure eligibility promotion when
  §4 gates pass. May be automatic on wave planning or an explicit operator
  "prepare wave" action; either way, only control-plane status changes — no Vamo
  writes.
- **`staging_canary_ready` → `staging_canary_approved`**: requires full §5 approval.
  Approval is recorded in the Confluendo control DB only (`ingestion_audit_log` +
  wave ledger). It does **not** write to Vamo staging.
- **`staging_canary_approved` → `staging_canary_running`**: set immediately before
  invoking `applyPostgresStagingCanary` for that unit.
- **Terminal per unit**: `staging_canary_succeeded` or `staging_canary_blocked`.
  Blocked units carry structured blockers on the queue row and in the wave item
  ledger.
- **No transition to `production_ready`, `applied`, or any production inbox state**
  in IP-18.5. Those remain IP-18.6+.

### 3.2 Wave-level status (new control table — design only)

Planned table: `ingestion_batch_staging_canary_waves`

| Wave status | Meaning |
| --- | --- |
| `planned` | Eligibility computed; no approval yet. |
| `approval_pending` | Awaiting or within approval freshness window. |
| `approved` | Approval recorded; eligible for execute. |
| `running` | At least one unit started; stop-on-failure active. |
| `succeeded` | All wave units reached `staging_canary_succeeded`. |
| `partial` | Some units succeeded, wave stopped on failure (see §6). |
| `failed` | No units succeeded (first unit blocked). |
| `blocked` | Approval/eligibility/ramp gate failed before execute. |

Wave status is derived from wave items plus approval state; it does not replace
per-unit queue status.

## 4. Eligibility

A queue unit may enter `staging_canary_ready` only when **all** of the following hold:

| Gate | Requirement |
| --- | --- |
| Prior status | `dry_run_succeeded` |
| Dry-run invariant | `run_report.wroteToTarget === false` (strict; missing report blocks) |
| Target environment | Explicit `target_environment = 'staging'` on the queue row — never inferred from `target_key` |
| Target key | Explicit `target_key = 'vamo-place-intelligence'` for the first consumer wave (profile key is not a substitute) |
| Dry-run success | Unit not `dry_run_blocked`; blockers array empty or only informational |
| Per-unit row bound | Planned shipment for the unit ≤ `STAGING_CANARY_MAX_ROWS` (50) — reuse IP-16 constant per unit |
| Wave row bound | Sum of planned write rows across selected units ≤ wave `maxTotalRows` cap |
| Wave unit bound | Selected unit count ≤ wave `maxUnits` cap |
| Safety mode | Batch plan and unit metadata remain `dry_run` at plan level; staging write happens only inside IP-16 adapter with `approved_write` |
| Production | Resolved environment must not be `production`; no production DSN, adapter, or control state |

Eligibility evaluation is a **pure policy module** (`evaluateBatchStagingCanaryWaveEligibility` —
name TBD in implementation). It has no DB or network access.

Blocked units stay at `dry_run_succeeded` (or move to `staging_canary_blocked` only
after a failed execute attempt) with ordered blocker codes surfaced in the dashboard.

## 5. Ramp policy

The first live staging wave must be **minimal**.

| Rule | First wave | Later waves |
| --- | --- | --- |
| Hard `maxUnits` cap | **1** | Operator-chosen, still bounded |
| Maximum without prior staging success | **1** for first live wave | Widening requires a **new explicit operator approval** with audit reason |
| Forbidden | Selecting all 33 remaining `dry_run_ready` units | Any wave that skips ramp approval when `maxUnits > priorApprovedMaxUnits` |
| Ordering | Deterministic: `run_order` asc, then `unit_key` asc | Same |

Ramp policy is separate from eligibility: a unit may be eligible but excluded from
the current wave because the wave's approved `maxUnits` / `maxTotalRows` cap is
lower than the eligible pool size.

Example first-live wave:

- `maxUnits = 1`
- `maxTotalRows = 50`
- `target_key = vamo-place-intelligence`
- `target_environment = staging`
- Unit: `vamo-place-intelligence:rome-italy:poi` (lowest `run_order` among the three
  `dry_run_succeeded` units)

## 6. Approval

Wave approval reuses IP-16 freshness semantics wherever possible:

| Gate | Requirement |
| --- | --- |
| Role | `ingestion_admin` (`admin` in allowlist) — same as IP-16 |
| MFA / AAL2 | Verified AAL2 required when MFA is required for the principal |
| Fresh step-up | Fresh MFA step-up within `STAGING_CANARY_FRESH_STEP_UP_WINDOW_MS` (30 minutes, mirrors IP-11) |
| Audit reason | Non-empty operator reason, recorded verbatim |
| Approval freshness | Recorded approval must be consumed within `STAGING_CANARY_APPROVAL_MAX_AGE_MS` (**15 minutes**, same as IP-16) |
| Scope | Approval names explicit `target_key`, `target_environment`, `maxUnits`, `maxTotalRows`, and optional unit allowlist |
| Storage | Approval decision writes **only** to Confluendo control DB (`approve_batch_staging_canary_wave` audit action) |
| Machine tokens | Cannot approve or execute waves |

Approval does **not** call `applyPostgresStagingCanary`. Execute is a separate,
confirmation-gated step (§10).

## 7. Partial failure — stop on first failure

**First implementation choice: stop-on-first-failure.**

When the wave executor runs approved units in order:

1. Skip units already at `staging_canary_succeeded`.
2. For each pending/approved unit, run the full IP-16 path.
3. On **first** unit failure (`staging_canary_blocked` or adapter error):
   - Mark that unit blocked with reason.
   - Set wave status to `partial` (if any prior unit succeeded) or `failed` (if none).
   - **Do not auto-execute** remaining units in the wave.
4. Units that succeeded before the failure **remain** `staging_canary_succeeded`
   with their shipment ledger intact.
5. Remaining not-yet-attempted units stay at `staging_canary_approved` (or revert
   to `staging_canary_ready` — implementation may choose; dashboard must show
   them as not executed).

Rationale: minimizes blast radius on the first consumer writes after dry-run-only
batch automation; operator must explicitly approve a follow-up wave or a narrowed
retry.

## 8. Resume and replay

| Scenario | Behavior |
| --- | --- |
| Re-run same wave execution key | Idempotent: skip `staging_canary_succeeded` units; attempt only pending/approved units |
| Per-unit shipment replay | `applyPostgresStagingCanary` idempotency on declared upsert keys — no duplicate staging rows |
| Shipment key | Stable per unit, e.g. `batch-staging-canary:{unitKey}:wave:{waveKey}:approval:{auditId}` |
| Wave ledger | `ingestion_batch_staging_canary_wave_items` (planned) stores unit outcome, linked `shipment_id`, blockers |
| Approval replay | Expired approval (> 15 minutes) blocks execute; operator must re-approve |
| Rollback | Per-unit via existing IP-16 rollback (`rollback_staging_canary`); wave orchestration does not bulk-rollback |

## 9. Relationship to IP-16

| Concern | Owner |
| --- | --- |
| Promotion gate, bounds, staging-only decision | `evaluateStagingCanaryPromotion()` — **reuse unchanged** |
| Staging sentinel proof + transactional upsert | `applyPostgresStagingCanary()` — **reuse unchanged** |
| Shipment ledger rows | Existing `ingestion_shipments` / `ingestion_shipment_items` — one shipment **per unit** |
| Approval audit actions (single-target) | IP-16 `approve_staging_canary` / `ship_staging_canary` — wave adds batch-scoped audit actions that **reference** IP-16 rows, not replace them |
| Rollback | IP-16 rollback path per unit |
| Batch eligibility, ramp, wave approval, ordering, stop-on-failure | **New IP-18.5 pure modules + control tables** |

IP-18.5 maps each batch queue unit's `run_report` + `proposal` into the
`ProgressiveRunReport` + `StagingCanaryBounds` shape IP-16 already accepts (one
geography, one category, and at most `STAGING_CANARY_MAX_ROWS`). If mapping
cannot satisfy IP-16 bounds, the unit is blocked before any adapter call.

**Anti-patterns (explicitly forbidden):**

- A single transaction writing multiple units' rows to Vamo staging.
- A new "batch staging write" adapter bypassing sentinel proof.
- Client-supplied row counts or environment strings trusted over server-derived
  queue metadata.
- Inferring `staging` from target key substrings.

## 10. Dashboard (read model — design)

Extend the IP-18 Batch Queue section on `/admin/ingestion` (read-only in IP-18.5.0;
mutation controls arrive in IP-18.5.1+):

| Surface | Content |
| --- | --- |
| Wave eligibility | Count of `dry_run_succeeded` units passing §4; excluded units with blocker codes |
| Target environment | Explicit `staging` badge — never derived from target key |
| Ramp hint | "First live wave: max 1 unit" when no prior wave succeeded |
| Approval state | Latest wave approval audit id, freshness countdown (15-minute window), approver |
| Execution state | Wave status, units succeeded / blocked / pending |
| Per-unit result | Staging shipment id, row counts, link to IP-16 rollback handle when succeeded |
| Per-unit blocker | Structured reason when `staging_canary_blocked` |

No provider buttons. No production inbox controls. Execute buttons (when added) must
be control-plane only until the CLI/runbook gate passes.

## 11. Ops and safety

### 11.1 Control schema (not applied in IP-18.5.0)

Implementation slice (IP-18.5.1+) will extend:

- `ingestion_batch_queue_items.status` CHECK — add staging-canary statuses from §3.1
- `ingestion_batch_staging_canary_waves` — wave ledger
- `ingestion_batch_staging_canary_wave_items` — per-unit outcomes, shipment links
- `control_bootstrap_confluendo.sql` grants for `confluendo_app`

That moves `CONTROL_TABLES` from **21 to 23**. The IP-18.5.1 done-state must
include a disposable-Postgres schema smoke that actually runs; skipped DB smokes
are not acceptable for the persistence slice.

Apply order on live Confluendo control DB (`confluendo-control`, ref
`agrcvzlkorlzwoxtkcft`):

1. Confirm SQL editor target is the control DB (role existence is not proof).
2. Apply updated `control_schema.sql`.
3. Re-run `control_bootstrap_confluendo.sql`.

### 11.2 Vamo staging readiness (before first live wave)

Same checklist as `STAGING_CANARY_RUNBOOK.md`:

- Staging DSN available server-side only (never in browser bundle).
- `confluendo_guard.environment_sentinel` present with `value='staging'`.
- Place-intelligence cache schema compatible with dry-run reports for selected units.
- `CONFIRM_VAMO_STAGING_CANARY=YES` remains required for live execute (per unit
  inside wave CLI, or once per wave if runbook documents a wave-level guard —
  implementation must not weaken IP-16 confirmation).

### 11.3 Production

- No production environment in wave specs, policies, or dashboard nodes.
- No `production_write`, production inbox, or `confluendo_inbox` paths in IP-18.5.
- `ip15:boundary-audit` must stay green.

### 11.4 Live wave execution (IP-18.5.2)

Preferred operator helper (Windows/PowerShell):

```powershell
cd Z:\vamo-ip17\web

# Read-only: inspect the target units and recent wave attempts.
.\scripts\Invoke-Ip18StagingWaveCycle.ps1 -Mode Status

# Control-plane only: reset selected units, rerun IP-18.4, and verify
# dry-run reports before asking for a fresh dashboard approval.
.\scripts\Invoke-Ip18StagingWaveCycle.ps1 -Mode PrepareDryRun

# After dashboard approval, execute the confirmation-gated 1-unit wave.
.\scripts\Invoke-Ip18StagingWaveCycle.ps1 `
  -Mode ExecuteWave `
  -ApprovalAuditId <approval-audit-id>
```

The helper intentionally does **not** create the dashboard approval. The admin +
AAL2 + fresh-MFA approval remains a human checkpoint. It only automates the
repeatable shell work around that checkpoint: env loading, stale queue reset,
IP-18.4 dry-run execution, report verification, and IP-18.5 execution after an
approval id is supplied. `PrepareDryRun` writes only Confluendo control-plane
state. `ExecuteWave` still requires `CONFIRM_CONFLUENDO_BATCH_STAGING_CANARY=YES`
internally and the Vamo staging canary app DSN.

Preview (CI-safe — no staging writes):

```powershell
$env:INGESTION_CONTROL_DATABASE_URL = "postgres://..."
npm --workspace @confluendo/ingestion-platform run ip18:staging-canary-wave -- `
  --wave-key batch-staging-canary:vamo-eu-poi-sample:audit:<approval-audit-id>
```

Execute against Vamo staging (manual only — requires ops sign-off):

```powershell
$env:CONFIRM_CONFLUENDO_BATCH_STAGING_CANARY = "YES"
$env:VAMO_STAGING_CANARY_ENVIRONMENT = "staging"
$env:VAMO_STAGING_CANARY_APP_DATABASE_URL = "<server-side staging DSN>"
$env:INGESTION_CONTROL_DATABASE_URL = "<confluendo control DSN>"
npm --workspace @confluendo/ingestion-platform run ip18:staging-canary-wave -- `
  --execute `
  --wave-key batch-staging-canary:vamo-eu-poi-sample:audit:<approval-audit-id> `
  --max-units 1 `
  --max-rows 50 `
  --audit-reason "First bounded staging-canary wave — 1 unit"
```

Live wave execute requires all of:

- Recorded wave approval within 15-minute freshness window
- `CONFIRM_CONFLUENDO_BATCH_STAGING_CANARY=YES`
- `VAMO_STAGING_CANARY_ENVIRONMENT=staging`
- Confluendo control DB URL + Vamo staging DSN (server-side)
- Explicit `--execute` (preview default)
- Per-unit `applyPostgresStagingCanary` with `confluendo_guard.environment_sentinel` proof
- Ramp bounds (`--max-units`, `--max-rows`) ≤ approved wave caps
- First live staging wave `maxUnits <= 1`; approval and execute both fail closed
  with `ramp_exceeded` before any Vamo staging write if this cap is exceeded

### 11.5 Staging grants (disposable Postgres / Vamo staging)

The ingestion role on the **target** DB needs:

```sql
create schema if not exists confluendo_guard;
create table if not exists confluendo_guard.environment_sentinel (
  key text primary key,
  value text not null
);
insert into confluendo_guard.environment_sentinel (key, value)
values ('environment', 'staging')
on conflict (key) do update set value = excluded.value;

grant usage on schema confluendo_guard to <ingestion_role>;
grant select on confluendo_guard.environment_sentinel to <ingestion_role>;
-- plus INSERT/UPDATE on target cache tables per STAGING_CANARY_RUNBOOK.md
```

## 12. Implementation phases (after IP-18.5.0)

| Phase | Slice | Deliverable |
| --- | --- | --- |
| 0 | **IP-18.5.0** (this doc) | Design spec, BUILD_SLICES + BATCH_TARGET_PLANNING updates |
| 1 | IP-18.5.1 | Pure wave eligibility + ramp + approval policy; control schema + persistence; unit tests |
| 2 | IP-18.5.2 | Wave executor calling `applyPostgresStagingCanary` per unit; disposable Postgres + fake-target smokes |
| 3 | IP-18.5.3 | Dashboard approval + execute controls; CLI `ip18:batch-staging-canary` preview/execute |
| 4 | IP-18.5.4 | Live first wave (1 unit) against Vamo staging after ops sign-off |

## 13. IP-18.5.0 acceptance criteria

- [x] Staging canary wave defined as independent per-unit IP-16 canaries — no aggregate write path.
- [x] State machine documented through `staging_canary_blocked` with extras not production states.
- [x] Eligibility, ramp, approval, partial failure, resume/replay, and IP-16
 relationship specified.
- [x] Dashboard read-model requirements documented.
- [x] Ops/schema/staging-readiness/production-forbidden rules documented.
- [x] IP-18.4 live evidence (audit 15, execution key, 3+33 queue split) recorded.
- [x] No functional code, SQL apply, or live execution in this slice.

## 14. Next slice

**IP-18.5.1 — Pure wave policy + control schema draft**: implement eligibility/ramp/
approval policies, add planned control tables to `control_schema.sql`, and land
disposable Postgres smokes — still **no live Vamo staging writes**.
