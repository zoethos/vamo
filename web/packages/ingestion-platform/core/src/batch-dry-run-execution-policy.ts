/**
 * Pure batch dry-run execution policy (IP-18.4).
 *
 * Selects bounded eligible queue units for control-plane dry-run execution.
 * No DB, network, provider, or target access.
 */

import type { BatchQueueItem, BatchQueueSnapshot } from "./batch-queue-read-model.js";

export type BatchDryRunExecutionBlockCode =
  | "audit_reason_required"
  | "unsafe_safety_mode"
  | "target_key_mismatch"
  | "target_environment_required"
  | "target_environment_mismatch"
  | "max_units_invalid"
  | "no_eligible_items";

export interface BatchDryRunExecutionBlock {
  code: BatchDryRunExecutionBlockCode;
  message: string;
}

export interface BatchDryRunExecutionPlan {
  action: "execute_batch_dry_run";
  executionKey: string;
  projectKey: string;
  queueId: string;
  planId: string;
  targetKey: string;
  targetEnvironment: string;
  sourceKey: string;
  maxUnits: number;
  fromStatus: "dry_run_ready";
  unitKeys: string[];
  selectedUnits: BatchQueueItem[];
  auditReason: string;
  auditId?: string;
  actor: { type: string; id: string };
  safetySummary: string[];
}

export type EvaluateBatchDryRunExecutionResult =
  | { ok: true; plan: BatchDryRunExecutionPlan }
  | { ok: false; blocks: BatchDryRunExecutionBlock[] };

export interface EvaluateBatchDryRunExecutionInput {
  projectKey: string;
  snapshot: BatchQueueSnapshot;
  targetKey: string;
  targetEnvironment: string;
  maxUnits: number;
  auditReason: string;
  auditId?: string;
  executionKey?: string;
  actor: { type: string; id: string };
}

const DEFAULT_SAFETY_SUMMARY = [
  "Control-plane dry-run execution only.",
  "No Vamo staging writes.",
  "No Vamo production writes.",
  "No live provider calls — fixture simulation only."
] as const;

export function evaluateBatchDryRunExecution(
  input: EvaluateBatchDryRunExecutionInput
): EvaluateBatchDryRunExecutionResult {
  const blocks: BatchDryRunExecutionBlock[] = [];
  const auditReason = input.auditReason.trim();

  if (!auditReason) {
    blocks.push({
      code: "audit_reason_required",
      message: "A non-empty audit reason is required to execute a batch dry run."
    });
  }

  if (input.snapshot.safetyMode !== "dry_run") {
    blocks.push({
      code: "unsafe_safety_mode",
      message: "Batch dry-run execution may only run for dry_run plans."
    });
  }

  if (input.snapshot.targetKey !== input.targetKey) {
    blocks.push({
      code: "target_key_mismatch",
      message: "Execution target key must match the active batch plan target key."
    });
  }

  if (!input.targetEnvironment) {
    blocks.push({
      code: "target_environment_required",
      message: "Execution requires an explicit target environment."
    });
  } else if (input.snapshot.targetEnvironment !== input.targetEnvironment) {
    blocks.push({
      code: "target_environment_mismatch",
      message: "Execution target environment must match the active batch plan."
    });
  }

  if (!Number.isFinite(input.maxUnits) || input.maxUnits < 1) {
    blocks.push({
      code: "max_units_invalid",
      message: "maxUnits must be a positive integer."
    });
  }

  const selectedUnits = input.snapshot.items
    .filter((item) => item.status === "dry_run_ready")
    .filter((item) => item.targetKey === input.targetKey)
    .filter((item) => item.targetEnvironment === input.targetEnvironment)
    .sort((a, b) => a.runOrder - b.runOrder)
    .slice(0, Math.max(0, input.maxUnits));

  if (selectedUnits.length === 0) {
    blocks.push({
      code: "no_eligible_items",
      message: "There are no dry_run_ready units matching the requested target and environment."
    });
  }

  if (blocks.length > 0) {
    return { ok: false, blocks };
  }

  const executionKey =
    input.executionKey?.trim() ||
    buildExecutionKey(input.auditId, input.snapshot.planId, selectedUnits.map((item) => item.unitKey));

  return {
    ok: true,
    plan: {
      action: "execute_batch_dry_run",
      executionKey,
      projectKey: input.projectKey,
      queueId: input.snapshot.queueId,
      planId: input.snapshot.planId,
      targetKey: input.targetKey,
      targetEnvironment: input.targetEnvironment,
      sourceKey: input.snapshot.sourceKey,
      maxUnits: input.maxUnits,
      fromStatus: "dry_run_ready",
      unitKeys: selectedUnits.map((item) => item.unitKey),
      selectedUnits,
      auditReason,
      auditId: input.auditId,
      actor: input.actor,
      safetySummary: [...DEFAULT_SAFETY_SUMMARY]
    }
  };
}

function buildExecutionKey(auditId: string | undefined, planId: string, unitKeys: string[]): string {
  if (auditId && auditId.trim().length > 0) {
    return `batch-dry-run:${planId}:audit:${auditId.trim()}`;
  }
  return `batch-dry-run:${planId}:${unitKeys.length}:${unitKeys[0] ?? "none"}`;
}
