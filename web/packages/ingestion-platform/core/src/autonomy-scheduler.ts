/**
 * Autonomy scheduler foundation (IP-18.7.3).
 *
 * Runs the existing one-cycle autonomy executor repeatedly until policy says to
 * pause, there is no eligible work, a human runbook is required, or a bounded
 * max-cycle limit is reached. This does not add a new write path.
 */

import {
  executeAutonomyCycle,
  previewAutonomyCycle,
  type AutonomyCycleBaseInput,
  type AutonomyCycleExecuteResult,
  type AutonomyCyclePreviewResult,
  type AutonomyExecutionChannel
} from "./autonomy-executor.js";
import type { AutonomyCycleDecision, AutonomyRequiredAction } from "./autonomy-policy.js";
import type { AutonomyRunPhase, AutonomyRunStatus } from "./control-models.js";

export const DEFAULT_AUTONOMY_SCHEDULER_MAX_CYCLES = 10;
export const MAX_AUTONOMY_SCHEDULER_CYCLES = 100;

export type AutonomySchedulerMode = "preview" | "execute";

export type AutonomySchedulerStopReason =
  | "preview_only"
  | "max_cycles_reached"
  | "policy_pause"
  | "no_eligible_work"
  | "human_runbook_required"
  | "idempotent_terminal_replay";

export interface AutonomySchedulerInput extends AutonomyCycleBaseInput {
  mode?: AutonomySchedulerMode;
  maxCycles?: number;
  intervalMs?: number;
  delay?: (ms: number) => Promise<void>;
}

export interface AutonomySchedulerCyclePreviewSummary {
  runKey: string;
  decision: AutonomyCycleDecision;
  phase: AutonomyRunPhase;
  requiredAction: AutonomyRequiredAction;
  selectedUnitKeys: string[];
  maxUnitsApplied: number;
  maxRowsApplied: number;
  executionChannel: AutonomyExecutionChannel;
  pauseReason?: string;
}

export interface AutonomySchedulerCycleExecuteSummary {
  runId: string;
  runStatus: AutonomyRunStatus;
  idempotentReplay: boolean;
  actionApplied: string | null;
  deferredReason?: string;
  auditId?: string | null;
  dryRunExecutionKey?: string | null;
  waveKey?: string | null;
  eventNames: string[];
}

export interface AutonomySchedulerCycleResult {
  cycleIndex: number;
  preview: AutonomySchedulerCyclePreviewSummary;
  execute?: AutonomySchedulerCycleExecuteSummary;
}

export interface AutonomySchedulerResult {
  ok: true;
  mode: AutonomySchedulerMode;
  policyKey: string;
  policyVersion: number;
  targetKey: string;
  targetEnvironment: string;
  maxCycles: number;
  cyclesEvaluated: number;
  actionsApplied: number;
  stopReason: AutonomySchedulerStopReason;
  cycles: AutonomySchedulerCycleResult[];
}

export async function runAutonomyScheduler(
  input: AutonomySchedulerInput
): Promise<AutonomySchedulerResult> {
  const mode = input.mode ?? "preview";
  const maxCycles = normalizeMaxCycles(input.maxCycles);
  const intervalMs = normalizeIntervalMs(input.intervalMs);
  const delay = input.delay ?? defaultDelay;
  const cycles: AutonomySchedulerCycleResult[] = [];
  let actionsApplied = 0;
  let stopReason: AutonomySchedulerStopReason = "preview_only";
  let policyKey = input.policyKey ?? "";
  let policyVersion = 0;
  let targetKey = input.targetKey ?? "";
  let targetEnvironment = "";

  for (let index = 1; index <= maxCycles; index += 1) {
    const preview = await previewAutonomyCycle(input);
    policyKey = preview.context.policy.policyKey;
    policyVersion = preview.context.policy.policyVersion;
    targetKey = preview.context.policy.targetKey;
    targetEnvironment = preview.context.policy.targetEnvironment;

    const cycle: AutonomySchedulerCycleResult = {
      cycleIndex: index,
      preview: summarizePreview(preview)
    };

    if (mode === "preview") {
      cycles.push(cycle);
      stopReason = "preview_only";
      break;
    }

    if (preview.context.evaluation.decision !== "continue") {
      const terminal = await executeAutonomyCycle(input);
      cycle.execute = summarizeExecute(terminal);
      cycles.push(cycle);
      stopReason = stopReasonForTerminalPreview(preview, terminal);
      break;
    }

    const executed = await executeAutonomyCycle(input);
    cycle.execute = summarizeExecute(executed);
    cycles.push(cycle);

    if (executed.actionApplied) {
      actionsApplied += 1;
    }

    if (executed.deferredReason) {
      stopReason = "human_runbook_required";
      break;
    }

    if (executed.idempotentReplay && executed.actionApplied === null) {
      stopReason = "idempotent_terminal_replay";
      break;
    }

    if (executed.context.executionChannel === "human_runbook") {
      stopReason = "human_runbook_required";
      break;
    }

    if (index === maxCycles) {
      stopReason = "max_cycles_reached";
      break;
    }

    if (intervalMs > 0) {
      await delay(intervalMs);
    }
  }

  return {
    ok: true,
    mode,
    policyKey,
    policyVersion,
    targetKey,
    targetEnvironment,
    maxCycles,
    cyclesEvaluated: cycles.length,
    actionsApplied,
    stopReason,
    cycles
  };
}

function normalizeMaxCycles(value: number | undefined): number {
  if (value === undefined) return DEFAULT_AUTONOMY_SCHEDULER_MAX_CYCLES;
  if (!Number.isInteger(value) || value < 1) {
    throw new Error("Autonomy scheduler maxCycles must be a positive integer.");
  }
  if (value > MAX_AUTONOMY_SCHEDULER_CYCLES) {
    throw new Error(
      `Autonomy scheduler maxCycles must be <= ${MAX_AUTONOMY_SCHEDULER_CYCLES}.`
    );
  }
  return value;
}

function normalizeIntervalMs(value: number | undefined): number {
  if (value === undefined) return 0;
  if (!Number.isInteger(value) || value < 0) {
    throw new Error("Autonomy scheduler intervalMs must be a non-negative integer.");
  }
  return value;
}

function summarizePreview(
  preview: AutonomyCyclePreviewResult
): AutonomySchedulerCyclePreviewSummary {
  return {
    runKey: preview.context.runKey,
    decision: preview.context.evaluation.decision,
    phase: preview.context.evaluation.phase,
    requiredAction: preview.context.evaluation.requiredAction,
    selectedUnitKeys: preview.context.evaluation.selectedUnitKeys,
    maxUnitsApplied: preview.context.evaluation.maxUnitsApplied,
    maxRowsApplied: preview.context.evaluation.maxRowsApplied,
    executionChannel: preview.context.executionChannel,
    pauseReason: preview.context.evaluation.pauseReason
  };
}

function summarizeExecute(
  result: AutonomyCycleExecuteResult
): AutonomySchedulerCycleExecuteSummary {
  return {
    runId: result.runId,
    runStatus: result.runStatus,
    idempotentReplay: result.idempotentReplay,
    actionApplied: result.actionApplied,
    deferredReason: result.deferredReason,
    auditId: result.auditId,
    dryRunExecutionKey: result.dryRunExecutionKey,
    waveKey: result.waveKey,
    eventNames: result.eventNames
  };
}

function stopReasonForTerminalPreview(
  preview: AutonomyCyclePreviewResult,
  execute: AutonomyCycleExecuteResult
): AutonomySchedulerStopReason {
  if (execute.idempotentReplay) return "idempotent_terminal_replay";
  if (preview.context.evaluation.decision === "no_op") return "no_eligible_work";
  return "policy_pause";
}

async function defaultDelay(ms: number): Promise<void> {
  await new Promise((resolve) => setTimeout(resolve, ms));
}
