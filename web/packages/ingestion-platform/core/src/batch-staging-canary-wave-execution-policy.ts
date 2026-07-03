/**
 * Pure batch staging-canary wave execution policy (IP-18.5.2).
 *
 * Selects approved wave items for confirmation-gated staging execution.
 * No DB, network, provider, or consumer target access.
 */

import { STAGING_CANARY_MAX_ROWS } from "./staging-canary-policy.js";
import { buildWaveUnitShipmentKey } from "./batch-staging-canary-wave-candidates.js";
import type { LoadedStagingCanaryWave, LoadedStagingCanaryWaveItem } from "./batch-staging-canary-wave-load.js";

export type BatchStagingCanaryWaveExecutionBlockCode =
  | "wave_not_found"
  | "wave_not_executable"
  | "approval_expired"
  | "production_environment_forbidden"
  | "target_environment_required"
  | "target_environment_mismatch"
  | "max_units_invalid"
  | "max_rows_invalid"
  | "approved_wave_bounds_exceeded"
  | "ramp_exceeded"
  | "no_pending_items";

export interface BatchStagingCanaryWaveExecutionBlock {
  code: BatchStagingCanaryWaveExecutionBlockCode;
  message: string;
}

export interface BatchStagingCanaryWaveExecutionUnitPlan {
  waveItemId: string;
  unitKey: string;
  runOrder: number;
  plannedRowCount: number;
  shipmentKey: string;
  status: "pending" | "skip_succeeded";
}

export interface BatchStagingCanaryWaveExecutionPlan {
  action: "execute_batch_staging_canary_wave";
  projectKey: string;
  waveId: string;
  waveKey: string;
  planKey: string;
  targetKey: string;
  targetEnvironment: "staging";
  approvalAuditId: string | null;
  maxUnits: number;
  maxRows: number;
  unitPlans: BatchStagingCanaryWaveExecutionUnitPlan[];
  pendingUnitKeys: string[];
  safetySummary: string[];
}

export type EvaluateBatchStagingCanaryWaveExecutionResult =
  | { ok: true; plan: BatchStagingCanaryWaveExecutionPlan }
  | { ok: false; blocks: BatchStagingCanaryWaveExecutionBlock[] };

export interface EvaluateBatchStagingCanaryWaveExecutionInput {
  projectKey: string;
  targetEnvironment: string;
  wave: LoadedStagingCanaryWave | null;
  maxUnits?: number;
  maxRows?: number;
  now?: string;
}

const EXECUTABLE_WAVE_STATUSES = new Set(["approved", "running", "partial"]);
const PENDING_ITEM_STATUSES = new Set(["approved"]);

const DEFAULT_SAFETY_SUMMARY = [
  "Per-unit applyPostgresStagingCanary only — no aggregate write path.",
  "Target DB must expose confluendo_guard.environment_sentinel value=staging.",
  "Stop-on-first-failure; skip already-succeeded wave items.",
  "No production writes. No live provider calls.",
  "Execute requires CONFIRM_CONFLUENDO_BATCH_STAGING_CANARY=YES and VAMO_STAGING_CANARY_APP_DATABASE_URL."
] as const;

const FIRST_WAVE_MAX_UNITS = 1;

export function evaluateBatchStagingCanaryWaveExecution(
  input: EvaluateBatchStagingCanaryWaveExecutionInput
): EvaluateBatchStagingCanaryWaveExecutionResult {
  const blocks: BatchStagingCanaryWaveExecutionBlock[] = [];
  const now = input.now ?? new Date().toISOString();

  if (!input.wave) {
    blocks.push({
      code: "wave_not_found",
      message: "No staging-canary wave matched the requested wave key or approval audit id."
    });
    return { ok: false, blocks };
  }

  if (input.targetEnvironment === "production") {
    blocks.push({
      code: "production_environment_forbidden",
      message: "Production is forbidden for batch staging-canary wave execution."
    });
  }

  if (!input.targetEnvironment) {
    blocks.push({
      code: "target_environment_required",
      message: "Wave execution requires an explicit target environment."
    });
  } else if (input.targetEnvironment !== "staging") {
    blocks.push({
      code: "target_environment_mismatch",
      message: "Batch staging-canary wave execution may only target explicit environment staging."
    });
  }

  if (!EXECUTABLE_WAVE_STATUSES.has(input.wave.status)) {
    blocks.push({
      code: "wave_not_executable",
      message: `Wave status "${input.wave.status}" is not executable (need approved/running/partial).`
    });
  }

  if (Date.parse(now) > Date.parse(input.wave.approvalExpiresAt)) {
    blocks.push({
      code: "approval_expired",
      message: "The wave approval freshness window has expired; re-approve before executing."
    });
  }

  const maxUnits = input.maxUnits ?? input.wave.maxUnits;
  const maxRows = input.maxRows ?? input.wave.maxRows;

  if (!Number.isFinite(maxUnits) || maxUnits < 1) {
    blocks.push({
      code: "max_units_invalid",
      message: "maxUnits must be a positive integer."
    });
  }

  if (!Number.isFinite(maxRows) || maxRows < 1) {
    blocks.push({
      code: "max_rows_invalid",
      message: "maxRows must be a positive integer."
    });
  }

  if (Number.isFinite(maxUnits) && maxUnits > input.wave.maxUnits) {
    blocks.push({
      code: "approved_wave_bounds_exceeded",
      message: `Requested maxUnits (${maxUnits}) exceeds the approved wave bound (${input.wave.maxUnits}).`
    });
  }

  if (Number.isFinite(maxRows) && maxRows > input.wave.maxRows) {
    blocks.push({
      code: "approved_wave_bounds_exceeded",
      message: `Requested maxRows (${maxRows}) exceeds the approved wave bound (${input.wave.maxRows}).`
    });
  }

  if (
    input.wave.priorSucceededUnitCount === 0 &&
    Number.isFinite(maxUnits) &&
    maxUnits > FIRST_WAVE_MAX_UNITS
  ) {
    blocks.push({
      code: "ramp_exceeded",
      message:
        "The first live staging-canary wave is hard-capped at 1 unit. Run and verify a 1-unit wave before widening."
    });
  }

  if (blocks.length > 0) {
    return { ok: false, blocks };
  }

  const unitPlans = buildUnitPlans(input.wave, maxUnits, maxRows);
  const pending = unitPlans.filter((plan) => plan.status === "pending");

  if (pending.length === 0) {
    blocks.push({
      code: "no_pending_items",
      message: "There are no approved wave items pending staging-canary execution."
    });
    return { ok: false, blocks };
  }

  return {
    ok: true,
    plan: {
      action: "execute_batch_staging_canary_wave",
      projectKey: input.projectKey,
      waveId: input.wave.id,
      waveKey: input.wave.waveKey,
      planKey: input.wave.planKey,
      targetKey: input.wave.targetKey,
      targetEnvironment: "staging",
      approvalAuditId: input.wave.approvalAuditId,
      maxUnits,
      maxRows,
      unitPlans,
      pendingUnitKeys: pending.map((plan) => plan.unitKey),
      safetySummary: [...DEFAULT_SAFETY_SUMMARY]
    }
  };
}

function buildUnitPlans(
  wave: LoadedStagingCanaryWave,
  maxUnits: number,
  maxRows: number
): BatchStagingCanaryWaveExecutionUnitPlan[] {
  const plans: BatchStagingCanaryWaveExecutionUnitPlan[] = [];
  let selectedUnits = 0;
  let selectedRows = 0;

  for (const item of wave.items.sort((a, b) => a.runOrder - b.runOrder)) {
    if (item.status === "succeeded") {
      plans.push(toUnitPlan(wave.waveKey, item, "skip_succeeded"));
      continue;
    }
    if (!PENDING_ITEM_STATUSES.has(item.status)) {
      continue;
    }
    if (selectedUnits >= maxUnits) {
      break;
    }
    const rowCount = Math.min(item.plannedRowCount, STAGING_CANARY_MAX_ROWS);
    if (selectedRows + rowCount > maxRows) {
      break;
    }
    plans.push(toUnitPlan(wave.waveKey, item, "pending"));
    selectedUnits += 1;
    selectedRows += rowCount;
  }

  return plans;
}

function toUnitPlan(
  waveKey: string,
  item: LoadedStagingCanaryWaveItem,
  status: BatchStagingCanaryWaveExecutionUnitPlan["status"]
): BatchStagingCanaryWaveExecutionUnitPlan {
  return {
    waveItemId: item.id,
    unitKey: item.unitKey,
    runOrder: item.runOrder,
    plannedRowCount: item.plannedRowCount,
    shipmentKey: buildWaveUnitShipmentKey(waveKey, item.unitKey),
    status
  };
}
