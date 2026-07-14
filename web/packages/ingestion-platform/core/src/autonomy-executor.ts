/**
 * Bounded autonomous batch executor (IP-18.7.1).
 *
 * Evaluates the active autonomy policy, records `ingestion_autonomy_runs` cycles,
 * and performs at most one bounded action per invocation. Never calls providers
 * or live staging canary execution. Production package delivery is available
 * only when the active policy and execution environment explicitly allow it.
 */

import { Client, type QueryResult } from "pg";

import {
  AUTONOMOUS_STAGING_WAVE_APPROVAL_MAX_UNITS,
  evaluateAutonomyCycle,
  type AutonomyPolicyEnvelope,
  type AutonomyRollingCounts,
  type EvaluateAutonomyCycleResult
} from "./autonomy-policy.js";
import {
  applyRampProfileToEnvelope,
  type EffectiveAutonomyRampEnvelope
} from "./autonomy-ramp-policy.js";
import {
  loadAutonomyPolicy,
  type AutonomyControlReadPgClientLike
} from "./autonomy-control-read.js";
import { resolveAutonomyExecutionChannel } from "./autonomy-read-model.js";
import type { AutonomyCycleEventName, AutonomyCycleTelemetryPayload } from "./autonomy-telemetry.js";
import type { BatchControlActor } from "./batch-control-actor.js";
import { executeBatchDryRun } from "./batch-dry-run-execution.js";
import { evaluateBatchDryRunExecution } from "./batch-dry-run-execution-policy.js";
import { extractBatchDryRunReportMetrics } from "./batch-dry-run-report-metrics.js";
import { approveBatchStagingCanaryWave } from "./batch-staging-canary-wave-control.js";
import type { BatchStagingCanaryWaveApprovalPlan } from "./batch-staging-canary-wave-policy.js";
import {
  approveBatchProductionPackageWave
} from "./batch-production-package-wave-control.js";
import {
  enrichProductionPackageWaveApprovalPlanWithStagedContentHashes
} from "./batch-production-package-wave-approval-content.js";
import { resolveSnapshotCandidateLoader } from "./activated-snapshot-candidate-loader.js";
import { loadActiveSnapshotReleasePlanBinding } from "./snapshot-release-plan-binding-read.js";
import { executeBatchProductionPackageWave } from "./batch-production-package-wave-delivery.js";
import { loadProductionPackageWaveApprovalContext } from "./batch-production-package-wave-read.js";
import {
  evaluateProductionPackageWaveEligibility,
  VAMO_PRODUCTION_PACKAGE_SCHEMA_CONTRACT,
  type BatchProductionPackageWaveApprovalPlan
} from "./batch-production-package-wave-policy.js";
import {
  STAGING_CANARY_APPROVAL_MAX_AGE_MS,
  STAGING_CANARY_MAX_ROWS
} from "./staging-canary-policy.js";
import { PRODUCTION_INBOX_APPROVAL_MAX_AGE_MS } from "./production-inbox-policy.js";
import { resolveAutonomyDrainBatchPlanKey } from "./batch-plan-selection.js";
import { loadBatchQueueSnapshot } from "./batch-queue-control-read.js";
import { scheduleBatchDryRun } from "./batch-queue-mutations.js";
import type { BatchQueueItem, BatchQueueSnapshot } from "./batch-queue-read-model.js";
import type { AutonomyRunStatus } from "./control-models.js";

export type AutonomyExecutionChannel = import("./autonomy-read-model.js").AutonomyExecutionChannel;

export interface AutonomyCycleContext {
  projectKey: string;
  policy: AutonomyPolicyEnvelope;
  queueSnapshot: BatchQueueSnapshot | null;
  evaluation: EvaluateAutonomyCycleResult;
  runKey: string;
  executionChannel: AutonomyExecutionChannel;
  rollingCounts: AutonomyRollingCounts;
  ownerCeiling?: EffectiveAutonomyRampEnvelope["ownerCeiling"];
  profileCaps?: EffectiveAutonomyRampEnvelope["profileCaps"];
}

export interface AutonomyCycleBaseInput {
  connectionString?: string;
  client?: AutonomyExecutorPgClientLike;
  productionInboxConnectionString?: string;
  productionInboxEnvironment?: string;
  projectKey: string;
  policyKey?: string;
  targetKey?: string;
  batchPlanKey?: string;
  artifactStoreDir?: string;
  artifactStore?: import("./snapshot-artifact-store.js").SnapshotArtifactStore;
  agentId: string;
  reason?: string;
  now?: string;
}

export interface AutonomyCyclePreviewResult {
  ok: true;
  mode: "preview";
  context: AutonomyCycleContext;
  writes: false;
}

export interface AutonomyCycleExecuteResult {
  ok: true;
  mode: "execute";
  context: AutonomyCycleContext;
  runId: string;
  runStatus: AutonomyRunStatus;
  idempotentReplay: boolean;
  actionApplied: string | null;
  deferredReason?: string;
  auditId?: string | null;
  dryRunExecutionKey?: string | null;
  waveKey?: string | null;
  packageKey?: string | null;
  eventNames: AutonomyCycleEventName[];
}

export type AutonomyCycleResult = AutonomyCyclePreviewResult | AutonomyCycleExecuteResult;

export interface AutonomyExecutorPgClientLike extends AutonomyControlReadPgClientLike {
  query<T extends Record<string, unknown> = Record<string, unknown>>(
    sql: string,
    values?: unknown[]
  ): Promise<QueryResult<T>>;
}

interface ProjectRow extends Record<string, unknown> {
  id: string;
}

interface ExistingRunRow extends Record<string, unknown> {
  id: string;
  status: AutonomyRunStatus;
  dryRunExecutionKey: string | null;
  waveKey: string | null;
  packageKey: string | null;
}

export function buildAutonomyRunKey(
  policy: AutonomyPolicyEnvelope,
  evaluation: EvaluateAutonomyCycleResult,
  executionChannel?: AutonomyExecutionChannel,
  now?: string
): string {
  const units = [...evaluation.selectedUnitKeys].sort().join(",");
  const evidence = evaluation.recommendedAction?.evidence as
    | { waveKey?: unknown; waveStatus?: unknown; packageKey?: unknown; packageId?: unknown }
    | undefined;
  const waveKey = typeof evidence?.waveKey === "string" ? evidence.waveKey : undefined;
  const waveStatus = typeof evidence?.waveStatus === "string" ? evidence.waveStatus : undefined;
  const packageKey = typeof evidence?.packageKey === "string" ? evidence.packageKey : undefined;
  const packageId = typeof evidence?.packageId === "string" ? evidence.packageId : undefined;
  const terminalWindow = buildTerminalWindowPart(evaluation, now);
  const parts = [
    "autonomy",
    policy.policyKey,
    `v${policy.policyVersion}`,
    `ramp:${policy.rampMode ?? "bootstrap"}`,
    evaluation.phase,
    evaluation.requiredAction,
    units || "none",
    executionChannel ? `channel:${executionChannel}` : undefined,
    terminalWindow,
    waveStatus ? `wave_status:${waveStatus}` : undefined,
    waveKey ? `wave:${waveKey}` : undefined,
    packageKey ? `package:${packageKey}` : undefined,
    packageId ? `package_id:${packageId}` : undefined
  ].filter((part): part is string => typeof part === "string" && part.length > 0);
  return parts.join(":");
}

function buildTerminalWindowPart(
  evaluation: EvaluateAutonomyCycleResult,
  now?: string
): string | undefined {
  if (evaluation.decision === "continue") {
    return undefined;
  }
  const timestamp = now ? Date.parse(now) : NaN;
  const date = Number.isFinite(timestamp) ? new Date(timestamp) : new Date();
  const day = date.toISOString().slice(0, 10);
  const pauseCode = evaluation.pauseReasonCode ?? evaluation.requiredAction;
  return `window:${day}:pause:${pauseCode}`;
}

export async function previewAutonomyCycle(
  input: AutonomyCycleBaseInput
): Promise<AutonomyCyclePreviewResult> {
  const context = await loadAutonomyCycleContext(input);
  return {
    ok: true,
    mode: "preview",
    context,
    writes: false
  };
}

export async function executeAutonomyCycle(
  input: AutonomyCycleBaseInput
): Promise<AutonomyCycleExecuteResult> {
  const { client, ownedClient } = await openClient(input.client, input.connectionString);
  const now = input.now ?? new Date().toISOString();
  const actor: BatchControlActor = { type: "autonomous_agent", id: input.agentId };

  try {
    const context = await loadAutonomyCycleContext({ ...input, client, now });
    const project = await loadProject(client, input.projectKey);
    if (!project) {
      throw new Error(`Unknown ingestion project "${input.projectKey}".`);
    }

    const existing = await loadExistingRun(client, context.policy.policyId, context.runKey);
    if (existing && isTerminalRunStatus(existing.status)) {
      return {
        ok: true,
        mode: "execute",
        context,
        runId: existing.id,
        runStatus: existing.status,
        idempotentReplay: true,
        actionApplied: null,
        dryRunExecutionKey: existing.dryRunExecutionKey,
        waveKey: existing.waveKey,
        packageKey: existing.packageKey,
        eventNames: []
      };
    }

    const runId =
      existing?.id ??
      (await insertAutonomyRun(client, {
        projectId: project.id,
        policy: context.policy,
        evaluation: context.evaluation,
        runKey: context.runKey,
        actor,
        now,
        status: "started"
      }));

    await insertAutonomyEvent(client, {
      projectId: project.id,
      eventName: "autonomy.cycle.started",
      evaluation: context.evaluation,
      policy: context.policy,
      runKey: context.runKey,
      actor,
      now
    });

    if (context.evaluation.decision === "pause") {
      const runStatus: AutonomyRunStatus = "paused";
      await finalizeAutonomyRun(client, {
        runId,
        evaluation: context.evaluation,
        status: runStatus,
        now
      });
      await insertAutonomyEvent(client, {
        projectId: project.id,
        eventName: "autonomy.cycle.paused",
        evaluation: context.evaluation,
        policy: context.policy,
        runKey: context.runKey,
        actor,
        now
      });
      return buildExecuteResult({
        context,
        runId,
        runStatus,
        idempotentReplay: false,
        actionApplied: null,
        eventNames: ["autonomy.cycle.started", "autonomy.cycle.paused"]
      });
    }

    if (context.evaluation.decision === "no_op") {
      const runStatus: AutonomyRunStatus = "completed";
      await finalizeAutonomyRun(client, {
        runId,
        evaluation: context.evaluation,
        status: runStatus,
        now
      });
      await insertAutonomyEvent(client, {
        projectId: project.id,
        eventName: "autonomy.cycle.completed",
        evaluation: context.evaluation,
        policy: context.policy,
        runKey: context.runKey,
        actor,
        now
      });
      return buildExecuteResult({
        context,
        runId,
        runStatus,
        idempotentReplay: false,
        actionApplied: null,
        eventNames: ["autonomy.cycle.started", "autonomy.cycle.completed"]
      });
    }

    if (context.executionChannel === "human_runbook") {
      const deferredReason =
        "Live staging-canary execution is deferred to the human confirmation-gated runbook.";
      const runStatus: AutonomyRunStatus = "skipped";
      await finalizeAutonomyRun(client, {
        runId,
        evaluation: context.evaluation,
        status: runStatus,
        pauseReason: deferredReason,
        now
      });
      await insertAutonomyEvent(client, {
        projectId: project.id,
        eventName: "autonomy.cycle.completed",
        evaluation: context.evaluation,
        policy: context.policy,
        runKey: context.runKey,
        actor,
        now,
        extra: { deferredReason }
      });
      return buildExecuteResult({
        context,
        runId,
        runStatus,
        idempotentReplay: false,
        actionApplied: null,
        deferredReason,
        eventNames: ["autonomy.cycle.started", "autonomy.cycle.completed"]
      });
    }

    let actionOutcome: ApplyAutonomyActionOutcome;
    try {
      actionOutcome = await applyAutonomyAction({
        client,
        input,
        context,
        actor,
        now
      });
    } catch (error) {
      const actionError = summarizeAutonomyActionError(error);
      const failureReason = `Autonomy action failed: ${actionError.message}`;
      const correctiveActions = [
        {
          action: "inspect_autonomy_action_failure",
          message:
            "Review the failed autonomy cycle evidence, fix the blocking control-plane condition, then rerun the same bounded cycle.",
          runKey: context.runKey,
          requiredAction: context.evaluation.requiredAction
        }
      ];
      await finalizeAutonomyRun(client, {
        runId,
        evaluation: context.evaluation,
        status: "failed",
        pauseReason: failureReason,
        guardOutcome: {
          actionError
        },
        correctiveActions,
        now
      });
      await insertAutonomyEvent(client, {
        projectId: project.id,
        eventName: "autonomy.cycle.failed",
        evaluation: context.evaluation,
        policy: context.policy,
        runKey: context.runKey,
        actor,
        now,
        extra: {
          actionError,
          correctiveActions
        }
      });
      throw error;
    }

    const runStatus: AutonomyRunStatus = actionOutcome.idempotentReplay ? "completed" : "advanced";
    await finalizeAutonomyRun(client, {
      runId,
      evaluation: context.evaluation,
      status: runStatus,
      dryRunExecutionKey: actionOutcome.dryRunExecutionKey ?? null,
      waveKey: actionOutcome.waveKey ?? null,
      packageKey: actionOutcome.packageKey ?? null,
      guardOutcome: actionOutcome.guardOutcome,
      now
    });

    await insertAutonomyEvent(client, {
      projectId: project.id,
      eventName: "autonomy.cycle.advanced",
      evaluation: context.evaluation,
      policy: context.policy,
      runKey: context.runKey,
      actor,
      now,
      extra: actionOutcome.telemetryEvidence
    });
    await insertAutonomyEvent(client, {
      projectId: project.id,
      eventName: "autonomy.action.applied",
      evaluation: context.evaluation,
      policy: context.policy,
      runKey: context.runKey,
      actor,
      now,
      extra: actionOutcome.telemetryEvidence
    });

    if (actionOutcome.auditId) {
      await insertAutonomyAudit(client, {
        projectId: project.id,
        actor,
        action: `autonomy.${actionOutcome.actionApplied}`,
        targetId: runId,
        reason: input.reason ?? context.policy.approvalReason ?? "Autonomous cycle action",
        payload: actionOutcome.telemetryEvidence,
        now
      });
    }

    return buildExecuteResult({
      context,
      runId,
      runStatus,
      idempotentReplay: actionOutcome.idempotentReplay,
      actionApplied: actionOutcome.actionApplied,
      auditId: actionOutcome.auditId,
      dryRunExecutionKey: actionOutcome.dryRunExecutionKey,
      waveKey: actionOutcome.waveKey,
      packageKey: actionOutcome.packageKey,
      eventNames: [
        "autonomy.cycle.started",
        "autonomy.cycle.advanced",
        "autonomy.action.applied"
      ]
    });
  } finally {
    await closeClient(ownedClient);
  }
}

async function loadAutonomyCycleContext(
  input: AutonomyCycleBaseInput & { client?: AutonomyExecutorPgClientLike }
): Promise<AutonomyCycleContext> {
  const { client, ownedClient } = await openClient(input.client, input.connectionString);

  try {
    const policy = await loadAutonomyPolicy(client, input);
    if (!policy) {
      throw new Error("No active autonomy policy matched the requested project/policy/target.");
    }
    if (policy.status !== "active") {
      throw new Error(`Autonomy policy "${policy.policyKey}" is ${policy.status}.`);
    }

    const batchPlanKey = resolveAutonomyDrainBatchPlanKey({
      policy,
      batchPlanKey: input.batchPlanKey
    });

    const queueSnapshot = await loadBatchQueueSnapshot({
      client,
      projectKey: input.projectKey,
      targetKey: policy.targetKey,
      planKey: batchPlanKey
    });
    const productionPackageApproval = queueSnapshot
      ? await loadProductionPackageWaveApprovalContext({
          client,
          projectKey: input.projectKey,
          targetKey: policy.targetKey
        })
      : null;

    const rampEnvelope = applyRampProfileToEnvelope(policy);
    const effectivePolicy = rampEnvelope.effective;
    const rollingCounts = await loadRollingCounts(client, effectivePolicy.policyId);
    const actor: BatchControlActor = { type: "autonomous_agent", id: input.agentId };
    const evaluation = evaluateAutonomyCycle({
      policy: effectivePolicy,
      queueSnapshot,
      latestDryRunExecution: queueSnapshot?.latestExecution,
      latestStagingWave: queueSnapshot?.latestWave,
      productionPackage: queueSnapshot?.latestProductionPackageWave,
      productionPackageApproval,
      rollingCounts,
      actor,
      now: input.now
    });

    const executionChannel = resolveAutonomyExecutionChannel(evaluation, queueSnapshot);
    const runKey = buildAutonomyRunKey(effectivePolicy, evaluation, executionChannel, input.now);

    return {
      projectKey: input.projectKey,
      policy: effectivePolicy,
      queueSnapshot,
      evaluation,
      runKey,
      executionChannel,
      rollingCounts,
      ownerCeiling: rampEnvelope.ownerCeiling,
      profileCaps: rampEnvelope.profileCaps
    };
  } finally {
    await closeClient(ownedClient);
  }
}

interface ApplyAutonomyActionInput {
  client: AutonomyExecutorPgClientLike;
  input: AutonomyCycleBaseInput;
  context: AutonomyCycleContext;
  actor: BatchControlActor;
  now: string;
}

interface ApplyAutonomyActionOutcome {
  actionApplied: string;
  idempotentReplay: boolean;
  auditId?: string | null;
  dryRunExecutionKey?: string | null;
  waveKey?: string | null;
  packageKey?: string | null;
  guardOutcome?: Record<string, unknown>;
  telemetryEvidence: Record<string, unknown>;
}

interface AutonomyActionErrorSummary extends Record<string, unknown> {
  name: string;
  message: string;
  code?: string;
}

async function applyAutonomyAction(
  params: ApplyAutonomyActionInput
): Promise<ApplyAutonomyActionOutcome> {
  const { context, input, actor, now } = params;
  const { evaluation, policy, queueSnapshot } = context;
  if (!queueSnapshot) {
    throw new Error("Batch queue snapshot is required to apply an autonomous action.");
  }

  const auditReason =
    input.reason?.trim() ||
    policy.approvalReason?.trim() ||
    `Autonomous cycle under policy ${policy.policyKey} v${policy.policyVersion}`;

  if (evaluation.requiredAction === "schedule_dry_run") {
    const boundedUnits = capSelectedUnits(queueSnapshot.items, evaluation, policy);
    const result = await scheduleBatchDryRun({
      client: params.client,
      projectKey: input.projectKey,
      planId: queueSnapshot.planId,
      targetKey: policy.targetKey,
      actor,
      reason: auditReason,
      unitKeys: boundedUnits.map((item) => item.unitKey),
      payload: {
        autonomyRunKey: context.runKey,
        policyKey: policy.policyKey,
        policyVersion: policy.policyVersion,
        targetEnvironment: policy.targetEnvironment,
        selectedUnitKeys: boundedUnits.map((item) => item.unitKey),
        maxUnitsApplied: evaluation.maxUnitsApplied,
        maxRowsApplied: evaluation.maxRowsApplied
      },
      now
    });
    return {
      actionApplied: "schedule_dry_run",
      idempotentReplay: result.scheduledCount === 0 && result.alreadyScheduledCount > 0,
      auditId: result.auditId,
      telemetryEvidence: {
        scheduledCount: result.scheduledCount,
        alreadyScheduledCount: result.alreadyScheduledCount,
        unitKeys: result.unitKeys
      }
    };
  }

  if (evaluation.requiredAction === "execute_dry_run") {
    const dryRunPlan = buildBoundedDryRunPlan({
      policy,
      queueSnapshot,
      evaluation,
      actor,
      auditReason
    });
    const result = await executeBatchDryRun({
      client: params.client,
      projectKey: input.projectKey,
      plan: dryRunPlan,
      now
    });
    return {
      actionApplied: "execute_dry_run",
      idempotentReplay: result.idempotentReplay,
      auditId: result.auditId,
      dryRunExecutionKey: result.executionKey,
      telemetryEvidence: {
        executionKey: result.executionKey,
        succeededCount: result.succeededCount,
        blockedCount: result.blockedCount,
        unitKeys: result.unitKeys,
        idempotentReplay: result.idempotentReplay
      },
      guardOutcome: { safetySummary: result.safetySummary }
    };
  }

  if (evaluation.requiredAction === "approve_or_execute_staging_wave_later") {
    const wavePlan = buildAutonomousStagingWavePlan({
      policy,
      queueSnapshot,
      evaluation,
      actor,
      auditReason,
      now
    });
    const result = await approveBatchStagingCanaryWave({
      client: params.client,
      projectKey: input.projectKey,
      plan: wavePlan,
      actor,
      now
    });
    return {
      actionApplied: "approve_staging_wave",
      idempotentReplay: result.idempotentReplay,
      auditId: result.auditId,
      waveKey: result.waveKey,
      telemetryEvidence: {
        waveKey: result.waveKey,
        waveId: result.waveId,
        unitKeys: result.unitKeys,
        idempotentReplay: result.idempotentReplay,
        note: "Control-plane wave approval only — live staging execution deferred."
      },
      guardOutcome: { safetySummary: wavePlan.safetySummary }
    };
  }

  if (evaluation.requiredAction === "approve_production_package_wave") {
    const packagePlan = await buildAutonomousProductionPackageWavePlan({
      client: params.client,
      policy,
      queueSnapshot,
      evaluation,
      actor,
      auditReason,
      artifactStoreDir: input.artifactStoreDir,
      now
    });
    const result = await approveBatchProductionPackageWave({
      client: params.client,
      projectKey: input.projectKey,
      plan: packagePlan,
      actor,
      now
    });
    return {
      actionApplied: "approve_production_package_wave",
      idempotentReplay: result.idempotentReplay,
      auditId: result.auditId,
      waveKey: result.waveKey,
      packageKey: result.waveKey,
      telemetryEvidence: {
        waveKey: result.waveKey,
        waveId: result.waveId,
        unitKeys: result.unitKeys,
        idempotentReplay: result.idempotentReplay,
        note: "Policy-authorized production package-wave approval only; inbox delivery is a separate action."
      },
      guardOutcome: { safetySummary: packagePlan.safetySummary }
    };
  }

  if (evaluation.requiredAction === "deliver_production_package_wave") {
    const productionPackage = queueSnapshot.latestProductionPackageWave;
    const waveKey = readStringEvidence(evaluation.recommendedAction?.evidence, "waveKey")
      ?? productionPackage?.waveKey;
    if (!waveKey) {
      throw new Error("Autonomous production package delivery requires a wave key.");
    }
    if (input.productionInboxEnvironment !== "production") {
      throw new Error(
        "Autonomous production package delivery requires VAMO_PRODUCTION_INBOX_ENVIRONMENT=production."
      );
    }
    if (!input.productionInboxConnectionString?.trim()) {
      throw new Error(
        "Autonomous production package delivery requires VAMO_PRODUCTION_INBOX_DATABASE_URL."
      );
    }
    const resolvedLoader = await resolveSnapshotCandidateLoader({
      client: params.client,
      controlConnectionString: input.connectionString,
      projectKey: input.projectKey,
      planKey: queueSnapshot.planId,
      artifactStoreDir: input.artifactStoreDir,
      artifactStore: input.artifactStore
    });
    try {
      const result = await executeBatchProductionPackageWave({
        controlClient: params.client,
        productionInboxConnectionString: input.productionInboxConnectionString,
        projectKey: input.projectKey,
        targetEnvironment: "production",
        waveKey,
        maxUnits: Math.max(1, evaluation.maxUnitsApplied),
        maxRows: Math.max(1, evaluation.maxRowsApplied),
        maxPackages: Math.max(1, evaluation.maxUnitsApplied),
        execute: true,
        actor,
        reason: auditReason,
        proveProduction: () => input.productionInboxEnvironment === "production",
        deps: {
          loadCandidates: resolvedLoader.loader
        },
        now
      });
      const firstPackage = result.unitResults.find((unit) => unit.packageKey);
      return {
        actionApplied: "deliver_production_package_wave",
        idempotentReplay: result.idempotentReplay,
        auditId: result.deliveryAuditId,
        waveKey: result.waveKey,
        packageKey: firstPackage?.packageKey ?? productionPackage?.packageKey ?? null,
        telemetryEvidence: {
          waveKey: result.waveKey,
          packageKey: firstPackage?.packageKey ?? productionPackage?.packageKey ?? null,
          deliveredCount: result.deliveredCount,
          skippedCount: result.skippedCount,
          blockedCount: result.blockedCount,
          idempotentReplay: result.idempotentReplay
        },
        guardOutcome: { safetySummary: result.safetySummary }
      };
    } finally {
      await resolvedLoader.dispose();
    }
  }

  throw new Error(
    `Autonomous executor cannot apply required action "${evaluation.requiredAction}" in IP-18.6.7.`
  );
}

function buildBoundedDryRunPlan(input: {
  policy: AutonomyPolicyEnvelope;
  queueSnapshot: BatchQueueSnapshot;
  evaluation: EvaluateAutonomyCycleResult;
  actor: BatchControlActor;
  auditReason: string;
}) {
  const selectedUnits = capSelectedUnits(
    input.queueSnapshot.items,
    input.evaluation,
    input.policy
  );
  const planResult = evaluateBatchDryRunExecution({
    projectKey: input.policy.projectKey,
    snapshot: {
      ...input.queueSnapshot,
      items: selectedUnits
    },
    targetKey: input.policy.targetKey,
    targetEnvironment: input.policy.targetEnvironment,
    maxUnits: input.policy.maxUnitsPerCycle,
    auditReason: input.auditReason,
    auditId: input.policy.approvedAuditId,
    executionKey: buildAutonomyDryRunExecutionKey(input.policy, input.evaluation),
    actor: input.actor
  });
  if (!planResult.ok) {
    throw new Error(
      `Dry-run execution plan blocked: ${planResult.blocks.map((block) => block.message).join("; ")}`
    );
  }
  if (planResult.plan.unitKeys.length > input.policy.maxUnitsPerCycle) {
    throw new Error("Dry-run plan exceeds policy max_units_per_cycle.");
  }
  return planResult.plan;
}

export function buildAutonomousStagingWavePlan(input: {
  policy: AutonomyPolicyEnvelope;
  queueSnapshot: BatchQueueSnapshot;
  evaluation: EvaluateAutonomyCycleResult;
  actor: BatchControlActor;
  auditReason: string;
  now: string;
}): BatchStagingCanaryWaveApprovalPlan {
  const selectedUnits = capSelectedUnits(
    input.queueSnapshot.items,
    input.evaluation,
    input.policy
  );
  let totalPlannedRows = 0;
  for (const item of selectedUnits) {
    const rows = item.dryRunReport
      ? item.dryRunReport.insertCount + item.dryRunReport.updateCount
      : 0;
    if (rows > STAGING_CANARY_MAX_ROWS) {
      throw new Error(`Unit "${item.unitKey}" exceeds STAGING_CANARY_MAX_ROWS.`);
    }
    totalPlannedRows += rows;
  }
  if (selectedUnits.length > input.policy.maxUnitsPerCycle) {
    throw new Error("Staging wave selection exceeds policy max_units_per_cycle.");
  }
  if (selectedUnits.length > AUTONOMOUS_STAGING_WAVE_APPROVAL_MAX_UNITS) {
    throw new Error(
      `Autonomous staging wave approval exceeds the first-wave cap of ${AUTONOMOUS_STAGING_WAVE_APPROVAL_MAX_UNITS} unit.`
    );
  }
  if (totalPlannedRows > input.policy.maxRowsPerCycle) {
    throw new Error("Staging wave selection exceeds policy max_rows_per_cycle.");
  }

  const unitKeys = selectedUnits.map((item) => item.unitKey);
  const waveKey = buildAutonomyWaveKey(input.policy, unitKeys);
  const approvedAt = input.now;
  const approvalExpiresAt = new Date(
    Date.parse(approvedAt) + STAGING_CANARY_APPROVAL_MAX_AGE_MS
  ).toISOString();

  return {
    action: "approve_batch_staging_canary_wave",
    waveKey,
    projectKey: input.policy.projectKey,
    queueId: input.queueSnapshot.queueId,
    planId: input.queueSnapshot.planId,
    targetKey: input.policy.targetKey,
    targetEnvironment: "staging",
    maxUnits: input.policy.maxUnitsPerCycle,
    maxRows: input.policy.maxRowsPerCycle,
    unitKeys,
    selectedUnits,
    totalPlannedRows,
    auditReason: input.auditReason,
    approvedAt,
    approvalExpiresAt,
    approvedBy: {
      email: input.actor.id,
      role: "autonomous_agent",
      assuranceLevel: "policy",
      policyApprovedBy: input.policy.approvedBy ?? null,
      policyApprovalAuditId: input.policy.approvedAuditId ?? null
    },
    safetySummary: [
      "Policy-authorized autonomous control-plane wave approval only.",
      "No Vamo staging writes in this autonomous action.",
      "Approval identity is the autonomous agent; the governing policy audit is referenced separately.",
      "Live staging execution requires the human confirmation-gated runbook."
    ]
  };
}

async function buildAutonomousProductionPackageWavePlan(input: {
  client: AutonomyExecutorPgClientLike;
  policy: AutonomyPolicyEnvelope;
  queueSnapshot: BatchQueueSnapshot;
  evaluation: EvaluateAutonomyCycleResult;
  actor: BatchControlActor;
  auditReason: string;
  artifactStoreDir?: string;
  now: string;
}): Promise<BatchProductionPackageWaveApprovalPlan> {
  const approvalContext = await loadProductionPackageWaveApprovalContext({
    client: input.client,
    projectKey: input.policy.projectKey,
    targetKey: input.policy.targetKey
  });

  const maxUnits = Math.max(1, input.evaluation.maxUnitsApplied);
  const maxRows = Math.max(1, input.evaluation.maxRowsApplied);
  const maxPackages = maxUnits;
  const eligibility = evaluateProductionPackageWaveEligibility({
    snapshot: input.queueSnapshot,
    targetKey: input.policy.targetKey,
    targetEnvironment: "production",
    schemaContract: VAMO_PRODUCTION_PACKAGE_SCHEMA_CONTRACT,
    maxUnits,
    maxRows,
    maxPackages,
    stagingEvidenceByUnitKey: approvalContext.stagingEvidenceByUnitKey,
    occupiedUnitKeys: approvalContext.occupiedUnitKeys,
    hasPriorDeliveredPackage: approvalContext.hasPriorDeliveredPackage
  });

  if (!eligibility.ok) {
    throw new Error(
      `Production package-wave approval blocked: ${eligibility.blocks.map((block) => block.message).join("; ")}`
    );
  }

  const selectedUnitKeys = new Set(input.evaluation.selectedUnitKeys);
  const selectedUnits = eligibility.selectedUnits.filter((unit) =>
    selectedUnitKeys.has(unit.item.unitKey)
  );
  if (selectedUnits.length === 0) {
    throw new Error("Production package-wave approval selected no eligible units.");
  }

  const approvedAt = input.now;
  const approvalExpiresAt = new Date(
    Date.parse(approvedAt) + PRODUCTION_INBOX_APPROVAL_MAX_AGE_MS
  ).toISOString();
  const plan: BatchProductionPackageWaveApprovalPlan = {
    action: "approve_batch_production_package_wave",
    waveKey: "",
    projectKey: input.policy.projectKey,
    queueId: input.queueSnapshot.queueId,
    planId: input.queueSnapshot.planId,
    targetKey: input.policy.targetKey,
    targetEnvironment: "production",
    schemaContract: VAMO_PRODUCTION_PACKAGE_SCHEMA_CONTRACT,
    maxUnits,
    maxRows,
    maxPackages,
    unitKeys: selectedUnits.map((unit) => unit.item.unitKey),
    selectedUnits: selectedUnits.map((unit) => ({ ...unit, plannedPackageKey: "" })),
    totalPlannedRows: selectedUnits.reduce((sum, unit) => sum + unit.writeCount, 0),
    auditReason: input.auditReason,
    approvedAt,
    approvalExpiresAt,
    approvedBy: {
      email: input.actor.id,
      role: "autonomous_agent",
      assuranceLevel: "policy",
      policyApprovedBy: input.policy.approvedBy ?? null,
      policyApprovalAuditId: input.policy.approvedAuditId ?? null
    },
    safetySummary: [
      "Policy-authorized autonomous production package-wave approval only.",
      "No production inbox write in this approval action.",
      "Approval identity is the autonomous agent; the governing policy audit is referenced separately.",
      "Inbox delivery requires a separate policy-authorized autonomy cycle and production proof."
    ]
  };

  const queueItemsByUnitKey = Object.fromEntries(
    input.queueSnapshot.items.map((item) => [item.unitKey, item])
  ) as Record<string, BatchQueueItem>;
  const activeRelease = await loadActiveSnapshotReleasePlanBinding({
    client: input.client,
    projectKey: input.policy.projectKey,
    planKey: input.queueSnapshot.planId
  });
  const loadCandidates = activeRelease
    ? async () => []
    : (
        await resolveSnapshotCandidateLoader({
          client: input.client,
          projectKey: input.policy.projectKey,
          planKey: input.queueSnapshot.planId
        })
      ).loader;
  return enrichProductionPackageWaveApprovalPlanWithStagedContentHashes({
    plan,
    queueItemsByUnitKey,
    loadCandidates,
    useRecordedStagingHashes: Boolean(activeRelease),
    stagingEvidenceByUnitKey: approvalContext.stagingEvidenceByUnitKey
  });
}

function buildAutonomyDryRunExecutionKey(
  policy: AutonomyPolicyEnvelope,
  evaluation: EvaluateAutonomyCycleResult
): string {
  const units = [...evaluation.selectedUnitKeys].sort().join(",");
  return `autonomy-dry-run:${policy.policyKey}:v${policy.policyVersion}:${units}`;
}

function buildAutonomyWaveKey(policy: AutonomyPolicyEnvelope, unitKeys: string[]): string {
  const sorted = [...unitKeys].sort();
  return `autonomy-wave:${policy.policyKey}:v${policy.policyVersion}:${sorted.join(",")}`;
}

function readStringEvidence(
  evidence: Record<string, unknown> | undefined,
  key: string
): string | undefined {
  const value = evidence?.[key];
  return typeof value === "string" && value.trim().length > 0 ? value : undefined;
}

function capSelectedUnits(
  items: BatchQueueItem[],
  evaluation: EvaluateAutonomyCycleResult,
  policy: AutonomyPolicyEnvelope
): BatchQueueItem[] {
  const selected = new Set(evaluation.selectedUnitKeys);
  const capped = items
    .filter((item) => selected.has(item.unitKey))
    .sort((a, b) => a.runOrder - b.runOrder)
    .slice(0, policy.maxUnitsPerCycle);

  let rows = 0;
  const bounded: BatchQueueItem[] = [];
  for (const item of capped) {
    const itemRows = extractBatchDryRunReportMetrics(item.dryRunReport)?.expectedTargetWrites ?? 1;
    if (rows + itemRows > policy.maxRowsPerCycle) {
      break;
    }
    bounded.push(item);
    rows += itemRows;
  }
  return bounded;
}

async function loadRollingCounts(
  client: AutonomyExecutorPgClientLike,
  policyId: string
): Promise<AutonomyRollingCounts> {
  const result = await client.query<{
    cyclesToday: string;
    unitsAdvancedToday: string;
    rowsAdvancedToday: string;
  }>(
    `
      select
        count(*) filter (where status in ('advanced', 'completed', 'failed'))::text as "cyclesToday",
        coalesce(sum(advanced_count) filter (where status in ('advanced', 'completed')), 0)::text as "unitsAdvancedToday",
        coalesce(sum((guard_outcome->>'rowsAdvanced')::int) filter (where status in ('advanced', 'completed')), 0)::text as "rowsAdvancedToday"
      from ingestion_platform.ingestion_autonomy_runs
      where policy_id = $1::bigint
        and created_at >= date_trunc('day', now())
    `,
    [policyId]
  );
  const row = result.rows[0];
  return {
    cyclesToday: Number(row?.cyclesToday ?? 0),
    unitsAdvancedToday: Number(row?.unitsAdvancedToday ?? 0),
    rowsAdvancedToday: Number(row?.rowsAdvancedToday ?? 0)
  };
}

async function loadExistingRun(
  client: AutonomyExecutorPgClientLike,
  policyId: string,
  runKey: string
): Promise<ExistingRunRow | undefined> {
  const result = await client.query<ExistingRunRow>(
    `
      select
        id::text as id,
        status,
        dry_run_execution_key as "dryRunExecutionKey",
        wave_key as "waveKey",
        package_key as "packageKey"
      from ingestion_platform.ingestion_autonomy_runs
      where policy_id = $1::bigint
        and run_key = $2
    `,
    [policyId, runKey]
  );
  return result.rows[0];
}

function isTerminalRunStatus(status: AutonomyRunStatus): boolean {
  return (
    status === "advanced" ||
    status === "completed" ||
    status === "paused" ||
    status === "skipped"
  );
}

async function insertAutonomyRun(
  client: AutonomyExecutorPgClientLike,
  input: {
    projectId: string;
    policy: AutonomyPolicyEnvelope;
    evaluation: EvaluateAutonomyCycleResult;
    runKey: string;
    actor: BatchControlActor;
    now: string;
    status: AutonomyRunStatus;
  }
): Promise<string> {
  const result = await client.query<{ id: string }>(
    `
      insert into ingestion_platform.ingestion_autonomy_runs (
        project_id,
        policy_id,
        run_key,
        phase,
        status,
        actor_type,
        actor_id,
        selected_units,
        scanned_count,
        advanced_count,
        blocked_count,
        skipped_count,
        highest_safety_mode,
        guard_outcome,
        pause_reason,
        recommended_action,
        telemetry_links,
        started_at,
        created_at,
        updated_at
      )
      values (
        $1::bigint,
        $2::bigint,
        $3,
        $4,
        $5,
        $6,
        $7,
        $8::jsonb,
        $9,
        0,
        $10,
        $11,
        $12,
        $13::jsonb,
        $14,
        $15::jsonb,
        $16::jsonb,
        $17::timestamptz,
        $17::timestamptz,
        $17::timestamptz
      )
      returning id::text as id
    `,
    [
      input.projectId,
      input.policy.policyId,
      input.runKey,
      input.evaluation.phase,
      input.status,
      input.actor.type,
      input.actor.id,
      JSON.stringify(input.evaluation.selectedUnitKeys),
      input.evaluation.scannedCount,
      input.evaluation.blockedCount,
      input.evaluation.skippedCount,
      input.evaluation.highestSafetyMode,
      JSON.stringify({
        decision: input.evaluation.decision,
        requiredAction: input.evaluation.requiredAction,
        maxUnitsApplied: input.evaluation.maxUnitsApplied,
        maxRowsApplied: input.evaluation.maxRowsApplied
      }),
      input.evaluation.pauseReason ?? null,
      input.evaluation.recommendedAction
        ? JSON.stringify(input.evaluation.recommendedAction)
        : null,
      JSON.stringify(input.evaluation.telemetry),
      input.now
    ]
  );
  const id = result.rows[0]?.id;
  if (!id) {
    throw new Error("Autonomy run row could not be created.");
  }
  return id;
}

async function finalizeAutonomyRun(
  client: AutonomyExecutorPgClientLike,
  input: {
    runId: string;
    evaluation: EvaluateAutonomyCycleResult;
    status: AutonomyRunStatus;
    pauseReason?: string;
    dryRunExecutionKey?: string | null;
    waveKey?: string | null;
    packageKey?: string | null;
    guardOutcome?: Record<string, unknown>;
    correctiveActions?: Record<string, unknown>[];
    now: string;
  }
): Promise<void> {
  await client.query(
    `
      update ingestion_platform.ingestion_autonomy_runs
      set status = $2,
          advanced_count = case when $2 = 'advanced' then greatest(advanced_count, $3) else advanced_count end,
          pause_reason = coalesce($4, pause_reason),
           dry_run_execution_key = coalesce($5, dry_run_execution_key),
          wave_key = coalesce($6, wave_key),
          package_key = coalesce($7, package_key),
           guard_outcome = guard_outcome || $8::jsonb,
           recommended_action = coalesce($9::jsonb, recommended_action),
           corrective_actions = case
             when $10::jsonb is null then corrective_actions
             else $10::jsonb
           end,
           completed_at = $11::timestamptz,
           updated_at = $11::timestamptz
       where id = $1::bigint
     `,
    [
      input.runId,
      input.status,
      input.evaluation.selectedUnitKeys.length,
      input.pauseReason ?? input.evaluation.pauseReason ?? null,
      input.dryRunExecutionKey ?? null,
      input.waveKey ?? null,
      input.packageKey ?? null,
      JSON.stringify({
        ...(input.guardOutcome ?? {}),
        rowsAdvanced: input.evaluation.maxRowsApplied
      }),
      input.evaluation.recommendedAction ? JSON.stringify(input.evaluation.recommendedAction) : null,
      input.correctiveActions ? JSON.stringify(input.correctiveActions) : null,
      input.now
    ]
  );
}

async function insertAutonomyEvent(
  client: AutonomyExecutorPgClientLike,
  input: {
    projectId: string;
    eventName: AutonomyCycleEventName;
    evaluation: EvaluateAutonomyCycleResult;
    policy: AutonomyPolicyEnvelope;
    runKey: string;
    actor: BatchControlActor;
    now: string;
    extra?: Record<string, unknown>;
  }
): Promise<void> {
  const payload: AutonomyCycleTelemetryPayload = {
    ...input.evaluation.telemetry,
    eventName: input.eventName,
    policyId: input.policy.policyId,
    policyKey: input.policy.policyKey,
    policyVersion: input.policy.policyVersion,
    runKey: input.runKey,
    projectKey: input.policy.projectKey,
    sourceKey: input.policy.sourceKey,
    targetKey: input.policy.targetKey,
    targetEnvironment: input.policy.targetEnvironment,
    actorType: input.actor.type,
    actorId: input.actor.id,
    decision: input.evaluation.decision,
    requiredAction: input.evaluation.requiredAction,
    selectedUnitKeys: input.evaluation.selectedUnitKeys,
    evidence: input.extra
  };
  const severity = input.eventName === "autonomy.cycle.failed" ? "error" : "info";

  await client.query(
    `
      insert into ingestion_platform.ingestion_events (
        project_id,
        event_type,
        severity,
        signal,
        message,
        payload,
        created_at
      )
      values ($1::bigint, $2, $3, 'autonomy_cycle', $4, $5::jsonb, $6::timestamptz)
    `,
    [
      input.projectId,
      input.eventName,
      severity,
      `Autonomy ${input.eventName} for ${input.policy.policyKey}`,
      JSON.stringify(payload),
      input.now
    ]
  );
}

function summarizeAutonomyActionError(error: unknown): AutonomyActionErrorSummary {
  if (error instanceof Error) {
    const summary: AutonomyActionErrorSummary = {
      name: error.name,
      message: error.message
    };
    const maybeCode = (error as { code?: unknown }).code;
    if (typeof maybeCode === "string" && maybeCode.length > 0) {
      summary.code = maybeCode;
    }
    return summary;
  }

  return {
    name: typeof error,
    message: String(error)
  };
}

async function insertAutonomyAudit(
  client: AutonomyExecutorPgClientLike,
  input: {
    projectId: string;
    actor: BatchControlActor;
    action: string;
    targetId: string;
    reason: string;
    payload: Record<string, unknown>;
    now: string;
  }
): Promise<void> {
  await client.query(
    `
      insert into ingestion_platform.ingestion_audit_log (
        project_id,
        actor_type,
        actor_id,
        action,
        target_type,
        target_id,
        reason,
        payload,
        created_at
      )
      values ($1::bigint, $2, $3, $4, 'autonomy_run', $5, $6, $7::jsonb, $8::timestamptz)
    `,
    [
      input.projectId,
      input.actor.type,
      input.actor.id,
      input.action,
      input.targetId,
      input.reason,
      JSON.stringify(input.payload),
      input.now
    ]
  );
}

async function loadProject(
  client: AutonomyExecutorPgClientLike,
  projectKey: string
): Promise<ProjectRow | undefined> {
  const result = await client.query<ProjectRow>(
    `
      select id::text as id
      from ingestion_platform.ingestion_projects
      where project_key = $1
    `,
    [projectKey]
  );
  return result.rows[0];
}

function buildExecuteResult(input: {
  context: AutonomyCycleContext;
  runId: string;
  runStatus: AutonomyRunStatus;
  idempotentReplay: boolean;
  actionApplied: string | null;
  deferredReason?: string;
  auditId?: string | null;
  dryRunExecutionKey?: string | null;
  waveKey?: string | null;
  packageKey?: string | null;
  eventNames: AutonomyCycleEventName[];
}): AutonomyCycleExecuteResult {
  return {
    ok: true,
    mode: "execute",
    context: input.context,
    runId: input.runId,
    runStatus: input.runStatus,
    idempotentReplay: input.idempotentReplay,
    actionApplied: input.actionApplied,
    deferredReason: input.deferredReason,
    auditId: input.auditId,
    dryRunExecutionKey: input.dryRunExecutionKey,
    waveKey: input.waveKey,
    packageKey: input.packageKey,
    eventNames: input.eventNames
  };
}

async function openClient(
  client?: AutonomyExecutorPgClientLike,
  connectionString?: string
): Promise<{ client: AutonomyExecutorPgClientLike; ownedClient?: Client }> {
  if (!client && !connectionString) {
    throw new Error("Autonomy executor requires a server-side connection string or client.");
  }
  const ownedClient = client ? undefined : new Client({ connectionString });
  const resolved = client ?? ownedClient;
  if (!resolved) {
    throw new Error("Autonomy executor client could not be initialized.");
  }
  if (ownedClient) {
    await ownedClient.connect();
  }
  return { client: resolved, ownedClient };
}

async function closeClient(client?: Client): Promise<void> {
  if (client) {
    await client.end();
  }
}
