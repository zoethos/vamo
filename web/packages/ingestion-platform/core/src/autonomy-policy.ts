/**
 * Pure autonomy cycle policy (IP-18.7).
 *
 * Chooses the next safe action or pause inside a human-approved policy envelope.
 * DB-free, deterministic, and reuses existing batch dry-run / staging policy
 * concepts. Does not execute writes in this slice.
 */

import type { CommandActorType } from "./commands.js";
import type {
  AutonomyPolicyStatus,
  AutonomyRunPhase
} from "./control-models.js";
import type { AutonomyRampMode } from "./autonomy-ramp-policy.js";
import { evaluateBatchDryRunExecution } from "./batch-dry-run-execution-policy.js";
import type {
  BatchQueueItem,
  BatchQueueLatestExecution,
  BatchQueueLatestWave,
  BatchQueueSnapshot
} from "./batch-queue-read-model.js";
import { extractBatchDryRunReportMetrics } from "./batch-dry-run-report-metrics.js";
import type { AutonomyCycleTelemetryPayload } from "./autonomy-telemetry.js";

export const AUTONOMOUS_STAGING_WAVE_APPROVAL_MAX_UNITS = 1;

export type AutonomyCycleDecision = "continue" | "pause" | "no_op";

export type AutonomyRequiredAction =
  | "schedule_dry_run"
  | "execute_dry_run"
  | "approve_or_execute_staging_wave_later"
  | "approve_production_package_wave"
  | "deliver_production_package_wave"
  | "apply_consumer_package"
  | "wait_for_human"
  | "pause_for_blocker"
  | "waiting_for_ip18_6";

export type AutonomyPauseReasonCode =
  | "policy_missing"
  | "policy_inactive"
  | "target_environment_mismatch"
  | "target_key_mismatch"
  | "source_key_mismatch"
  | "queue_blockers"
  | "external_blockers"
  | "rolling_limit_exceeded"
  | "bounds_exceeded"
  | "transition_not_allowed"
  | "missing_prior_evidence"
  | "production_inbox_not_executable"
  | "actor_not_autonomous"
  | "no_eligible_work";

export interface AutonomyPolicyEnvelope {
  policyId: string;
  policyKey: string;
  projectKey: string;
  sourceKey: string;
  targetKey: string;
  targetEnvironment: "staging" | "production";
  status: AutonomyPolicyStatus;
  allowedTiers: string[];
  allowedGeographies: string[];
  allowedCategories: string[];
  allowedTransitions: string[];
  maxUnitsPerCycle: number;
  maxRowsPerCycle: number;
  rollingLimits: Record<string, unknown>;
  guardThresholds: Record<string, unknown>;
  productionInboxHandoffPolicy: Record<string, unknown>;
  policyVersion: number;
  rampMode?: AutonomyRampMode;
  approvedBy?: string;
  approvedAuditId?: string;
  approvalReason?: string;
  batchPlanKey?: string;
  summary?: Record<string, unknown>;
}

export interface AutonomyRollingCounts {
  unitsAdvancedToday?: number;
  rowsAdvancedToday?: number;
  cyclesToday?: number;
}

export interface AutonomyActorContext {
  type: CommandActorType;
  id: string;
}

export interface AutonomyProductionPackageState {
  packageKey?: string | null;
  packageId?: string | null;
  waveKey?: string;
  status?: string;
  targetEnvironment?: string;
  approvalAuditId?: string | null;
  deliveryAuditId?: string | null;
  deliveryStatus?: string | null;
  consumerApplyStatus?: string | null;
  unitCount?: number;
  totalPlannedRows?: number;
  maxUnits?: number;
  maxRows?: number;
  maxPackages?: number;
  items?: Array<{
    unitKey: string;
    status: string;
    plannedRowCount?: number;
    packageKey?: string | null;
    packageId?: string | null;
    blockers?: string[];
    consumerApplyStatus?: string | null;
  }>;
}

export interface EvaluateAutonomyCycleInput {
  policy: AutonomyPolicyEnvelope | null;
  queueSnapshot: BatchQueueSnapshot | null;
  latestDryRunExecution?: BatchQueueLatestExecution | null;
  latestStagingWave?: BatchQueueLatestWave | null;
  productionPackage?: AutonomyProductionPackageState | null;
  rollingCounts?: AutonomyRollingCounts;
  externalBlockers?: string[];
  actor: AutonomyActorContext;
  now?: string;
}

export interface AutonomyRecommendedAction {
  action: AutonomyRequiredAction;
  summary: string;
  evidence?: Record<string, unknown>;
}

export interface EvaluateAutonomyCycleResult {
  decision: AutonomyCycleDecision;
  phase: AutonomyRunPhase;
  selectedUnitKeys: string[];
  maxUnitsApplied: number;
  maxRowsApplied: number;
  requiredAction: AutonomyRequiredAction;
  pauseReason?: string;
  pauseReasonCode?: AutonomyPauseReasonCode;
  recommendedAction?: AutonomyRecommendedAction;
  telemetry: AutonomyCycleTelemetryPayload;
  scannedCount: number;
  blockedCount: number;
  skippedCount: number;
  highestSafetyMode: "dry_run" | "staging_write" | "production_write";
}

const PLANNING_TRANSITION = "schedule_dry_run";
const DRY_RUN_TRANSITION = "execute_dry_run";
const STAGING_TRANSITION = "approve_staging_wave";
const PRODUCTION_PACKAGE_APPROVAL_TRANSITION = "approve_production_package_wave";
const PRODUCTION_PACKAGE_DELIVERY_TRANSITION = "deliver_production_package_wave";
const CONSUMER_APPLY_TRANSITION = "apply_consumer_package";
const PACKAGE_DELIVERY_READY_STATUSES = new Set(["approved", "delivering"]);
const PACKAGE_APPLY_PENDING_STATUSES = new Set([
  "delivered",
  "consumer_apply_pending"
]);
const PACKAGE_BLOCKED_STATUSES = new Set(["blocked", "consumer_apply_failed"]);

export function evaluateAutonomyCycle(input: EvaluateAutonomyCycleInput): EvaluateAutonomyCycleResult {
  const baseTelemetry = buildBaseTelemetry(input);

  if (!input.policy) {
    return pauseResult({
      phase: "planning",
      pauseReasonCode: "policy_missing",
      pauseReason: "No autonomy policy envelope is configured for this source/target pair.",
      requiredAction: "wait_for_human",
      recommendedAction: {
        action: "wait_for_human",
        summary: "Create and approve an ingestion_autonomy_policies row before autonomous cycles."
      },
      telemetry: {
        ...baseTelemetry,
        eventName: "autonomy.cycle.paused",
        decision: "pause",
        pauseReason: "policy_missing"
      }
    });
  }

  const policy = input.policy;

  if (policy.status !== "active") {
    return pauseResult({
      phase: "planning",
      pauseReasonCode: "policy_inactive",
      pauseReason: `Autonomy policy "${policy.policyKey}" is ${policy.status}; only active policies may advance work.`,
      requiredAction: "wait_for_human",
      recommendedAction: {
        action: "wait_for_human",
        summary: "Reactivate or replace the autonomy policy after operator review.",
        evidence: { policyStatus: policy.status, policyKey: policy.policyKey }
      },
      telemetry: {
        ...baseTelemetry,
        eventName: "autonomy.cycle.paused",
        decision: "pause",
        pauseReason: "policy_inactive",
        policyId: policy.policyId,
        policyKey: policy.policyKey,
        policyVersion: policy.policyVersion
      }
    });
  }

  if (input.actor.type !== "autonomous_agent") {
    return pauseResult({
      phase: "planning",
      pauseReasonCode: "actor_not_autonomous",
      pauseReason: "Autonomous cycle evaluation for execution requires actor_type autonomous_agent.",
      requiredAction: "wait_for_human",
      telemetry: {
        ...baseTelemetry,
        eventName: "autonomy.cycle.paused",
        decision: "pause",
        pauseReason: "actor_not_autonomous",
        actorType: input.actor.type,
        actorId: input.actor.id
      }
    });
  }

  if (!input.queueSnapshot) {
    return pauseResult({
      phase: "planning",
      pauseReasonCode: "missing_prior_evidence",
      pauseReason: "Batch queue snapshot is required to evaluate the next autonomy cycle.",
      requiredAction: "pause_for_blocker",
      telemetry: {
        ...baseTelemetry,
        eventName: "autonomy.cycle.paused",
        decision: "pause",
        pauseReason: "missing_prior_evidence"
      }
    });
  }

  const snapshot = input.queueSnapshot;
  const envelopeMismatches = validatePolicyEnvelope(policy, snapshot);
  if (envelopeMismatches.length > 0) {
    const top = envelopeMismatches[0]!;
    return pauseResult({
      phase: "planning",
      pauseReasonCode: top.code,
      pauseReason: top.message,
      requiredAction: "pause_for_blocker",
      recommendedAction: {
        action: "pause_for_blocker",
        summary: top.message,
        evidence: { mismatches: envelopeMismatches.map((m) => m.code) }
      },
      telemetry: {
        ...baseTelemetry,
        eventName: "autonomy.cycle.paused",
        decision: "pause",
        pauseReason: top.code
      }
    });
  }

  const externalBlockers = input.externalBlockers ?? [];
  if (externalBlockers.length > 0) {
    return pauseResult({
      phase: "corrective_action",
      pauseReasonCode: "external_blockers",
      pauseReason: `External blockers present: ${externalBlockers.join("; ")}`,
      requiredAction: "pause_for_blocker",
      recommendedAction: {
        action: "pause_for_blocker",
        summary: "Resolve external blockers before resuming autonomous cycles.",
        evidence: { blockers: externalBlockers }
      },
      scannedCount: snapshot.items.length,
      blockedCount: externalBlockers.length,
      telemetry: {
        ...baseTelemetry,
        eventName: "autonomy.cycle.paused",
        decision: "pause",
        pauseReason: "external_blockers"
      }
    });
  }

  if (snapshot.blockerSummaries.length > 0 || snapshot.progress.blocked > 0) {
    const top = snapshot.blockerSummaries[0];
    return pauseResult({
      phase: "corrective_action",
      pauseReasonCode: "queue_blockers",
      pauseReason: top
        ? `Queue blockers present — top: ${top.reason} (${top.count} unit(s)).`
        : "Queue units are blocked.",
      requiredAction: "pause_for_blocker",
      recommendedAction: {
        action: "pause_for_blocker",
        summary: "Resolve queue blockers before the agent advances the batch.",
        evidence: { blockerSummaries: snapshot.blockerSummaries }
      },
      scannedCount: snapshot.items.length,
      blockedCount: snapshot.progress.blocked,
      telemetry: {
        ...baseTelemetry,
        eventName: "autonomy.cycle.paused",
        decision: "pause",
        pauseReason: "queue_blockers"
      }
    });
  }

  const rollingViolation = checkRollingLimits(policy, input.rollingCounts);
  if (rollingViolation) {
    return pauseResult({
      phase: "planning",
      pauseReasonCode: "rolling_limit_exceeded",
      pauseReason: rollingViolation,
      requiredAction: "wait_for_human",
      recommendedAction: {
        action: "wait_for_human",
        summary: rollingViolation,
        evidence: { rollingLimits: policy.rollingLimits, rollingCounts: input.rollingCounts }
      },
      scannedCount: snapshot.items.length,
      telemetry: {
        ...baseTelemetry,
        eventName: "autonomy.cycle.paused",
        decision: "pause",
        pauseReason: "rolling_limit_exceeded"
      }
    });
  }

  const inScopeItems = filterItemsToPolicyEnvelope(snapshot.items, policy);
  const maxUnits = policy.maxUnitsPerCycle;
  const maxRows = policy.maxRowsPerCycle;

  const readyForSchedule = selectBoundedUnits(
    inScopeItems.filter((item) => item.status === "ready_for_dry_run"),
    maxUnits,
    maxRows
  );
  if (readyForSchedule.length > 0 && policy.allowedTransitions.includes(PLANNING_TRANSITION)) {
    return continueResult({
      phase: "planning",
      requiredAction: "schedule_dry_run",
      selectedUnitKeys: readyForSchedule.map((item) => item.unitKey),
      maxUnitsApplied: Math.min(maxUnits, readyForSchedule.length),
      maxRowsApplied: sumPlannedRows(readyForSchedule, maxRows),
      highestSafetyMode: "dry_run",
      scannedCount: snapshot.items.length,
      skippedCount: snapshot.items.length - readyForSchedule.length,
      recommendedAction: {
        action: "schedule_dry_run",
        summary: `Schedule ${readyForSchedule.length} unit(s) for dry-run inside policy bounds.`,
        evidence: { unitKeys: readyForSchedule.map((item) => item.unitKey) }
      },
      telemetry: {
        ...baseTelemetry,
        eventName: "autonomy.cycle.advanced",
        decision: "continue",
        phase: "planning",
        requiredAction: "schedule_dry_run",
        selectedUnitKeys: readyForSchedule.map((item) => item.unitKey),
        policyId: policy.policyId,
        policyKey: policy.policyKey,
        policyVersion: policy.policyVersion
      }
    });
  }

  const dryRunPlan = evaluateBatchDryRunExecution({
    projectKey: policy.projectKey,
    snapshot: {
      ...snapshot,
      items: inScopeItems
    },
    targetKey: policy.targetKey,
    targetEnvironment: policy.targetEnvironment,
    maxUnits,
    auditReason: autonomyAuditReason(policy),
    auditId: policy.approvedAuditId,
    actor: { type: input.actor.type, id: input.actor.id }
  });

  if (
    dryRunPlan.ok &&
    policy.allowedTransitions.includes(DRY_RUN_TRANSITION) &&
    dryRunPlan.plan.unitKeys.length > 0
  ) {
    const bounded = capDryRunSelection(dryRunPlan.plan.selectedUnits, maxUnits, maxRows);
    if (bounded.unitKeys.length === 0) {
      return pauseForBounds(policy, snapshot, baseTelemetry);
    }
    return continueResult({
      phase: "dry_run",
      requiredAction: "execute_dry_run",
      selectedUnitKeys: bounded.unitKeys,
      maxUnitsApplied: bounded.maxUnits,
      maxRowsApplied: bounded.maxRows,
      highestSafetyMode: "dry_run",
      scannedCount: snapshot.items.length,
      skippedCount: snapshot.items.length - bounded.unitKeys.length,
      recommendedAction: {
        action: "execute_dry_run",
        summary: `Execute dry-run for ${bounded.unitKeys.length} dry_run_ready unit(s) within policy bounds.`,
        evidence: {
          executionKey: dryRunPlan.plan.executionKey,
          unitKeys: bounded.unitKeys
        }
      },
      telemetry: {
        ...baseTelemetry,
        eventName: "autonomy.cycle.advanced",
        decision: "continue",
        phase: "dry_run",
        requiredAction: "execute_dry_run",
        selectedUnitKeys: bounded.unitKeys,
        policyId: policy.policyId,
        policyKey: policy.policyKey,
        policyVersion: policy.policyVersion,
        evidence: { executionKey: dryRunPlan.plan.executionKey }
      }
    });
  }

  const stagingEligible = selectStagingEligibleUnits(
    inScopeItems,
    Math.min(maxUnits, AUTONOMOUS_STAGING_WAVE_APPROVAL_MAX_UNITS),
    maxRows
  );
  if (stagingEligible.length > 0) {
    if (policy.targetEnvironment !== "staging") {
      return pauseResult({
        phase: "staging_canary",
        pauseReasonCode: "target_environment_mismatch",
        pauseReason: "Staging-canary work requires policy target_environment staging.",
        requiredAction: "pause_for_blocker",
        scannedCount: snapshot.items.length,
        telemetry: {
          ...baseTelemetry,
          eventName: "autonomy.cycle.paused",
          decision: "pause",
          pauseReason: "target_environment_mismatch"
        }
      });
    }

    if (!policy.allowedTransitions.includes(STAGING_TRANSITION)) {
      return pauseResult({
        phase: "staging_canary",
        pauseReasonCode: "transition_not_allowed",
        pauseReason: "Policy does not allow approve_staging_wave transitions.",
        requiredAction: "wait_for_human",
        scannedCount: snapshot.items.length,
        telemetry: {
          ...baseTelemetry,
          eventName: "autonomy.cycle.paused",
          decision: "pause",
          pauseReason: "transition_not_allowed"
        }
      });
    }

    const wave = input.latestStagingWave;
    if (wave && ["approved", "running"].includes(wave.status)) {
      return continueResult({
        phase: "staging_canary",
        requiredAction: "approve_or_execute_staging_wave_later",
        selectedUnitKeys: stagingEligible.map((item) => item.unitKey),
        maxUnitsApplied: Math.min(maxUnits, stagingEligible.length),
        maxRowsApplied: sumPlannedRows(stagingEligible, maxRows),
        highestSafetyMode: "staging_write",
        scannedCount: snapshot.items.length,
        recommendedAction: {
          action: "approve_or_execute_staging_wave_later",
          summary: `Approved wave ${wave.waveKey} is ${wave.status}; live staging execution remains confirmation-gated.`,
          evidence: { waveKey: wave.waveKey, waveStatus: wave.status }
        },
        telemetry: {
          ...baseTelemetry,
          eventName: "autonomy.cycle.advanced",
          decision: "continue",
          phase: "staging_canary",
          requiredAction: "approve_or_execute_staging_wave_later",
          evidence: { waveKey: wave.waveKey }
        }
      });
    }

    return continueResult({
      phase: "staging_canary",
      requiredAction: "approve_or_execute_staging_wave_later",
      selectedUnitKeys: stagingEligible.map((item) => item.unitKey),
      maxUnitsApplied: Math.min(maxUnits, stagingEligible.length),
      maxRowsApplied: sumPlannedRows(stagingEligible, maxRows),
      highestSafetyMode: "staging_write",
      scannedCount: snapshot.items.length,
      recommendedAction: {
        action: "approve_or_execute_staging_wave_later",
        summary: `${stagingEligible.length} dry_run_succeeded unit(s) eligible; human-approved staging wave required before live writes.`,
        evidence: { unitKeys: stagingEligible.map((item) => item.unitKey) }
      },
      telemetry: {
        ...baseTelemetry,
        eventName: "autonomy.cycle.advanced",
        decision: "continue",
        phase: "staging_canary",
        requiredAction: "approve_or_execute_staging_wave_later",
        selectedUnitKeys: stagingEligible.map((item) => item.unitKey)
      }
    });
  }

  const productionPackage = input.productionPackage ?? null;
  const packageBlocker = productionPackage ? readProductionPackageBlocker(productionPackage) : null;
  if (packageBlocker) {
    return pauseResult({
      phase: "production_inbox",
      pauseReasonCode: "queue_blockers",
      pauseReason: packageBlocker,
      requiredAction: "pause_for_blocker",
      scannedCount: snapshot.items.length,
      recommendedAction: {
        action: "pause_for_blocker",
        summary: "Resolve production package or consumer apply blockers before the agent advances delivery.",
        evidence: {
          waveKey: productionPackage?.waveKey,
          packageKey: productionPackage?.packageKey,
          packageStatus: productionPackage?.status,
          consumerApplyStatus: productionPackage?.consumerApplyStatus
        }
      },
      telemetry: {
        ...baseTelemetry,
        eventName: "autonomy.cycle.paused",
        decision: "pause",
        phase: "production_inbox",
        pauseReason: "queue_blockers",
        requiredAction: "pause_for_blocker"
      }
    });
  }

  if (productionPackage && PACKAGE_DELIVERY_READY_STATUSES.has(productionPackage.status ?? "")) {
    if (!productionHandoffEnabled(policy)) {
      return pauseProductionHandoffDisabled(policy, snapshot, baseTelemetry, productionPackage);
    }
    if (!policy.allowedTransitions.includes(PRODUCTION_PACKAGE_DELIVERY_TRANSITION)) {
      return pauseProductionTransitionNotAllowed(
        policy,
        snapshot,
        baseTelemetry,
        PRODUCTION_PACKAGE_DELIVERY_TRANSITION,
        productionPackage
      );
    }
    const selectedUnitKeys = productionPackage.items?.map((item) => item.unitKey) ?? [];
    const plannedRows = readPositiveNumber(productionPackage.totalPlannedRows)
      ?? sumPackageItemRows(productionPackage)
      ?? Math.min(policy.maxRowsPerCycle, 1);
    return continueResult({
      phase: "production_inbox",
      requiredAction: "deliver_production_package_wave",
      selectedUnitKeys,
      maxUnitsApplied: Math.min(
        policy.maxUnitsPerCycle,
        selectedUnitKeys.length || productionPackage.unitCount || 1
      ),
      maxRowsApplied: Math.min(policy.maxRowsPerCycle, plannedRows),
      highestSafetyMode: "production_write",
      scannedCount: snapshot.items.length,
      recommendedAction: {
        action: "deliver_production_package_wave",
        summary: `Deliver approved production package wave ${productionPackage.waveKey ?? "(unknown wave)"} inside policy bounds.`,
        evidence: {
          waveKey: productionPackage.waveKey,
          packageKey: productionPackage.packageKey,
          packageId: productionPackage.packageId,
          approvalAuditId: productionPackage.approvalAuditId,
          packageStatus: productionPackage.status
        }
      },
      telemetry: {
        ...baseTelemetry,
        eventName: "autonomy.cycle.advanced",
        decision: "continue",
        phase: "production_inbox",
        requiredAction: "deliver_production_package_wave",
        selectedUnitKeys,
        evidence: {
          waveKey: productionPackage.waveKey,
          packageKey: productionPackage.packageKey
        }
      }
    });
  }

  if (productionPackage && packageNeedsConsumerApply(productionPackage)) {
    if (!consumerApplyAutonomyEnabled(policy)) {
      return pauseResult({
        phase: "production_inbox",
        pauseReasonCode: "production_inbox_not_executable",
        pauseReason:
          "Production package is delivered, but consumer apply remains consumer-owned until the autonomy policy explicitly enables autonomous apply.",
        requiredAction: "apply_consumer_package",
        scannedCount: snapshot.items.length,
        recommendedAction: {
          action: "apply_consumer_package",
          summary: "Use the Apply to Vamo control or enable consumerApplyEnabled in the human-approved policy.",
          evidence: {
            waveKey: productionPackage.waveKey,
            packageId: productionPackage.packageId,
            consumerApplyStatus: productionPackage.consumerApplyStatus
          }
        },
        telemetry: {
          ...baseTelemetry,
          eventName: "autonomy.cycle.paused",
          decision: "pause",
          phase: "production_inbox",
          pauseReason: "production_inbox_not_executable",
          requiredAction: "apply_consumer_package"
        }
      });
    }
    if (!policy.allowedTransitions.includes(CONSUMER_APPLY_TRANSITION)) {
      return pauseProductionTransitionNotAllowed(
        policy,
        snapshot,
        baseTelemetry,
        CONSUMER_APPLY_TRANSITION,
        productionPackage
      );
    }
    return pauseResult({
      phase: "production_inbox",
      pauseReasonCode: "production_inbox_not_executable",
      pauseReason:
        "Autonomous consumer apply execution is intentionally not implemented in IP-18.6.7; use the gated console apply control.",
      requiredAction: "apply_consumer_package",
      scannedCount: snapshot.items.length,
      recommendedAction: {
        action: "apply_consumer_package",
        summary: "Consumer apply is ready but remains gated by the consumer-owned apply control.",
        evidence: {
          waveKey: productionPackage.waveKey,
          packageId: productionPackage.packageId,
          consumerApplyStatus: productionPackage.consumerApplyStatus
        }
      },
      telemetry: {
        ...baseTelemetry,
        eventName: "autonomy.cycle.paused",
        decision: "pause",
        phase: "production_inbox",
        pauseReason: "production_inbox_not_executable",
        requiredAction: "apply_consumer_package"
      }
    });
  }

  const productionReady = selectProductionPackageEligibleUnits(inScopeItems, maxUnits, maxRows);
  if (productionReady.length > 0) {
    if (!productionHandoffEnabled(policy)) {
      return pauseProductionHandoffDisabled(policy, snapshot, baseTelemetry, productionPackage);
    }
    if (!policy.allowedTransitions.includes(PRODUCTION_PACKAGE_APPROVAL_TRANSITION)) {
      return pauseProductionTransitionNotAllowed(
        policy,
        snapshot,
        baseTelemetry,
        PRODUCTION_PACKAGE_APPROVAL_TRANSITION,
        productionPackage
      );
    }
    return continueResult({
      phase: "production_inbox",
      requiredAction: "approve_production_package_wave",
      selectedUnitKeys: productionReady.map((item) => item.unitKey),
      maxUnitsApplied: Math.min(maxUnits, productionReady.length),
      maxRowsApplied: sumPlannedRows(productionReady, maxRows),
      highestSafetyMode: "production_write",
      scannedCount: snapshot.items.length,
      skippedCount: snapshot.items.length - productionReady.length,
      recommendedAction: {
        action: "approve_production_package_wave",
        summary: `${productionReady.length} staging-verified unit(s) eligible for a production package-wave approval.`,
        evidence: {
          unitKeys: productionReady.map((item) => item.unitKey),
          targetEnvironment: "production"
        }
      },
      telemetry: {
        ...baseTelemetry,
        eventName: "autonomy.cycle.advanced",
        decision: "continue",
        phase: "production_inbox",
        requiredAction: "approve_production_package_wave",
        selectedUnitKeys: productionReady.map((item) => item.unitKey)
      }
    });
  }

  if (policy.allowedTransitions.includes("deliver_production_inbox")) {
    return pauseResult({
      phase: "production_inbox",
      pauseReasonCode: "transition_not_allowed",
      pauseReason:
        "Legacy deliver_production_inbox transition does not authorize package-wave production delivery.",
      requiredAction: "wait_for_human",
      scannedCount: snapshot.items.length,
      recommendedAction: {
        action: "wait_for_human",
        summary:
          "Replace deliver_production_inbox with approve_production_package_wave and deliver_production_package_wave in the approved policy.",
        evidence: { allowedTransitions: policy.allowedTransitions }
      },
      telemetry: {
        ...baseTelemetry,
        eventName: "autonomy.cycle.paused",
        decision: "pause",
        phase: "production_inbox",
        pauseReason: "transition_not_allowed",
        requiredAction: "wait_for_human"
      }
    });
  }

  return {
    decision: "no_op",
    phase: "planning",
    selectedUnitKeys: [],
    maxUnitsApplied: 0,
    maxRowsApplied: 0,
    requiredAction: "wait_for_human",
    scannedCount: snapshot.items.length,
    blockedCount: 0,
    skippedCount: snapshot.items.length,
    highestSafetyMode: "dry_run",
    recommendedAction: {
      action: "wait_for_human",
      summary: "No eligible units inside the approved autonomy envelope."
    },
    telemetry: {
      ...baseTelemetry,
      eventName: "autonomy.cycle.completed",
      decision: "no_op",
      phase: "planning"
    }
  };
}

function validatePolicyEnvelope(
  policy: AutonomyPolicyEnvelope,
  snapshot: BatchQueueSnapshot
): Array<{ code: AutonomyPauseReasonCode; message: string }> {
  const mismatches: Array<{ code: AutonomyPauseReasonCode; message: string }> = [];

  if (snapshot.sourceKey !== policy.sourceKey) {
    mismatches.push({
      code: "source_key_mismatch",
      message: "Queue source key does not match the active autonomy policy."
    });
  }
  if (snapshot.targetKey !== policy.targetKey) {
    mismatches.push({
      code: "target_key_mismatch",
      message: "Queue target key does not match the active autonomy policy."
    });
  }
  if (snapshot.targetEnvironment !== policy.targetEnvironment) {
    mismatches.push({
      code: "target_environment_mismatch",
      message:
        "Queue target environment does not match the policy envelope. Environment is never inferred from target key text."
    });
  }

  return mismatches;
}

function filterItemsToPolicyEnvelope(
  items: BatchQueueItem[],
  policy: AutonomyPolicyEnvelope
): BatchQueueItem[] {
  const geographies =
    policy.allowedGeographies.length > 0 ? new Set(policy.allowedGeographies) : null;
  const categories =
    policy.allowedCategories.length > 0 ? new Set(policy.allowedCategories) : null;

  return items.filter((item) => {
    if (item.sourceKey !== policy.sourceKey) return false;
    if (item.targetKey !== policy.targetKey) return false;
    if (item.targetEnvironment !== policy.targetEnvironment) return false;
    if (geographies && !geographies.has(item.country) && !geographies.has(item.geography)) {
      return false;
    }
    if (categories && !categories.has(item.category)) return false;
    return true;
  });
}

function selectBoundedUnits(
  items: BatchQueueItem[],
  maxUnits: number,
  maxRows: number
): BatchQueueItem[] {
  const selected: BatchQueueItem[] = [];
  let rows = 0;
  for (const item of [...items].sort((a, b) => a.runOrder - b.runOrder)) {
    if (selected.length >= maxUnits) break;
    const itemRows = plannedRowsForItem(item);
    if (rows + itemRows > maxRows) break;
    selected.push(item);
    rows += itemRows;
  }
  return selected;
}

function selectStagingEligibleUnits(
  items: BatchQueueItem[],
  maxUnits: number,
  maxRows: number
): BatchQueueItem[] {
  const eligible = items.filter(
    (item) =>
      item.status === "dry_run_succeeded" &&
      item.dryRunReport?.wroteToTarget === false
  );
  return selectBoundedUnits(eligible, maxUnits, maxRows);
}

function selectProductionPackageEligibleUnits(
  items: BatchQueueItem[],
  maxUnits: number,
  maxRows: number
): BatchQueueItem[] {
  const eligible = items.filter(
    (item) =>
      (item.status === "staging_canary_succeeded" || item.status === "production_package_ready") &&
      item.dryRunReport?.wroteToTarget === false &&
      item.blockReasons.length === 0
  );
  return selectBoundedUnits(eligible, maxUnits, maxRows);
}

function productionHandoffEnabled(policy: AutonomyPolicyEnvelope): boolean {
  const handoff = policy.productionInboxHandoffPolicy ?? {};
  if (handoff.requiresIp18_6 === true || handoff.requiresIp18_6 === "true") {
    return false;
  }
  return handoff.enabled === true;
}

function consumerApplyAutonomyEnabled(policy: AutonomyPolicyEnvelope): boolean {
  const handoff = policy.productionInboxHandoffPolicy ?? {};
  return productionHandoffEnabled(policy) && handoff.consumerApplyEnabled === true;
}

function readProductionPackageBlocker(
  productionPackage: AutonomyProductionPackageState
): string | null {
  if (PACKAGE_BLOCKED_STATUSES.has(productionPackage.status ?? "")) {
    return `Production package wave is ${productionPackage.status}.`;
  }
  if (productionPackage.consumerApplyStatus === "failed") {
    return "Consumer apply failed for the latest production package.";
  }
  const blockedItem = productionPackage.items?.find(
    (item) => item.status === "blocked" || (item.blockers?.length ?? 0) > 0
  );
  if (blockedItem) {
    return `Production package item ${blockedItem.unitKey} is blocked.`;
  }
  return null;
}

function packageNeedsConsumerApply(productionPackage: AutonomyProductionPackageState): boolean {
  return (
    PACKAGE_APPLY_PENDING_STATUSES.has(productionPackage.status ?? "") ||
    productionPackage.deliveryStatus === "production_inbox_delivered" ||
    productionPackage.consumerApplyStatus === "pending"
  );
}

function sumPackageItemRows(productionPackage: AutonomyProductionPackageState): number | null {
  const rows = productionPackage.items?.reduce(
    (sum, item) => sum + (item.plannedRowCount ?? 0),
    0
  );
  return rows && rows > 0 ? rows : null;
}

function readPositiveNumber(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) && value > 0 ? value : null;
}

function capDryRunSelection(
  units: BatchQueueItem[],
  maxUnits: number,
  maxRows: number
): { unitKeys: string[]; maxUnits: number; maxRows: number } {
  const bounded = selectBoundedUnits(units, maxUnits, maxRows);
  return {
    unitKeys: bounded.map((item) => item.unitKey),
    maxUnits: bounded.length,
    maxRows: sumPlannedRows(bounded, maxRows)
  };
}

function plannedRowsForItem(item: BatchQueueItem): number {
  return extractBatchDryRunReportMetrics(item.dryRunReport)?.expectedTargetWrites ?? 1;
}

function sumPlannedRows(items: BatchQueueItem[], cap: number): number {
  return Math.min(cap, items.reduce((sum, item) => sum + plannedRowsForItem(item), 0));
}

function checkRollingLimits(
  policy: AutonomyPolicyEnvelope,
  counts: AutonomyRollingCounts | undefined
): string | undefined {
  if (!counts) return undefined;
  const limits = policy.rollingLimits;
  const maxUnitsPerDay = readPositiveLimit(limits, "maxUnitsPerDay");
  const maxRowsPerDay = readPositiveLimit(limits, "maxRowsPerDay");
  const maxCyclesPerDay = readPositiveLimit(limits, "maxCyclesPerDay");

  if (maxUnitsPerDay !== undefined && (counts.unitsAdvancedToday ?? 0) >= maxUnitsPerDay) {
    return `Rolling daily unit limit (${maxUnitsPerDay}) would be exceeded.`;
  }
  if (maxRowsPerDay !== undefined && (counts.rowsAdvancedToday ?? 0) >= maxRowsPerDay) {
    return `Rolling daily row limit (${maxRowsPerDay}) would be exceeded.`;
  }
  if (maxCyclesPerDay !== undefined && (counts.cyclesToday ?? 0) >= maxCyclesPerDay) {
    return `Rolling daily cycle limit (${maxCyclesPerDay}) would be exceeded.`;
  }
  return undefined;
}

function readPositiveLimit(limits: Record<string, unknown>, key: string): number | undefined {
  const value = limits[key];
  if (typeof value === "number" && Number.isFinite(value) && value > 0) {
    return value;
  }
  return undefined;
}

function autonomyAuditReason(policy: AutonomyPolicyEnvelope): string {
  if (policy.approvalReason && policy.approvalReason.trim().length > 0) {
    return policy.approvalReason.trim();
  }
  return `Autonomous dry-run cycle under policy ${policy.policyKey} v${policy.policyVersion}`;
}

function buildBaseTelemetry(input: EvaluateAutonomyCycleInput): AutonomyCycleTelemetryPayload {
  return {
    eventName: "autonomy.cycle.started",
    projectKey: input.policy?.projectKey ?? input.queueSnapshot?.projectKey,
    sourceKey: input.policy?.sourceKey ?? input.queueSnapshot?.sourceKey,
    targetKey: input.policy?.targetKey ?? input.queueSnapshot?.targetKey,
    targetEnvironment: input.policy?.targetEnvironment ?? input.queueSnapshot?.targetEnvironment,
    actorType: input.actor.type,
    actorId: input.actor.id,
    policyId: input.policy?.policyId,
    policyKey: input.policy?.policyKey,
    policyVersion: input.policy?.policyVersion
  };
}

function pauseForBounds(
  policy: AutonomyPolicyEnvelope,
  snapshot: BatchQueueSnapshot,
  baseTelemetry: AutonomyCycleTelemetryPayload
): EvaluateAutonomyCycleResult {
  return pauseResult({
    phase: "dry_run",
    pauseReasonCode: "bounds_exceeded",
    pauseReason: `Dry-run selection would exceed max_units_per_cycle (${policy.maxUnitsPerCycle}) or max_rows_per_cycle (${policy.maxRowsPerCycle}).`,
    requiredAction: "wait_for_human",
    scannedCount: snapshot.items.length,
    recommendedAction: {
      action: "wait_for_human",
      summary: "Narrow the policy bounds or wait for smaller eligible units."
    },
    telemetry: {
      ...baseTelemetry,
      eventName: "autonomy.cycle.paused",
      decision: "pause",
      pauseReason: "bounds_exceeded",
      policyId: policy.policyId,
      policyKey: policy.policyKey
    }
  });
}

function pauseProductionHandoffDisabled(
  policy: AutonomyPolicyEnvelope,
  snapshot: BatchQueueSnapshot,
  baseTelemetry: AutonomyCycleTelemetryPayload,
  productionPackage: AutonomyProductionPackageState | null
): EvaluateAutonomyCycleResult {
  return pauseResult({
    phase: "production_inbox",
    pauseReasonCode: "production_inbox_not_executable",
    pauseReason:
      "Production package autonomy is disabled by the active policy envelope.",
    requiredAction: "wait_for_human",
    scannedCount: snapshot.items.length,
    recommendedAction: {
      action: "wait_for_human",
      summary:
        "An admin operator must explicitly enable productionInboxHandoffPolicy.enabled before the agent can advance production packages.",
      evidence: {
        productionInboxHandoffPolicy: policy.productionInboxHandoffPolicy,
        waveKey: productionPackage?.waveKey,
        packageStatus: productionPackage?.status
      }
    },
    telemetry: {
      ...baseTelemetry,
      eventName: "autonomy.cycle.paused",
      decision: "pause",
      phase: "production_inbox",
      pauseReason: "production_inbox_not_executable",
      requiredAction: "wait_for_human"
    }
  });
}

function pauseProductionTransitionNotAllowed(
  policy: AutonomyPolicyEnvelope,
  snapshot: BatchQueueSnapshot,
  baseTelemetry: AutonomyCycleTelemetryPayload,
  transition: string,
  productionPackage: AutonomyProductionPackageState | null
): EvaluateAutonomyCycleResult {
  return pauseResult({
    phase: "production_inbox",
    pauseReasonCode: "transition_not_allowed",
    pauseReason: `Policy does not allow ${transition} transitions.`,
    requiredAction: "wait_for_human",
    scannedCount: snapshot.items.length,
    recommendedAction: {
      action: "wait_for_human",
      summary: `Add ${transition} to the human-approved policy before the agent can advance this production phase.`,
      evidence: {
        allowedTransitions: policy.allowedTransitions,
        waveKey: productionPackage?.waveKey,
        packageStatus: productionPackage?.status
      }
    },
    telemetry: {
      ...baseTelemetry,
      eventName: "autonomy.cycle.paused",
      decision: "pause",
      phase: "production_inbox",
      pauseReason: "transition_not_allowed",
      requiredAction: "wait_for_human"
    }
  });
}

function pauseResult(input: {
  phase: AutonomyRunPhase;
  pauseReasonCode: AutonomyPauseReasonCode;
  pauseReason: string;
  requiredAction: AutonomyRequiredAction;
  recommendedAction?: AutonomyRecommendedAction;
  scannedCount?: number;
  blockedCount?: number;
  skippedCount?: number;
  telemetry: AutonomyCycleTelemetryPayload;
}): EvaluateAutonomyCycleResult {
  return {
    decision: "pause",
    phase: input.phase,
    selectedUnitKeys: [],
    maxUnitsApplied: 0,
    maxRowsApplied: 0,
    requiredAction: input.requiredAction,
    pauseReason: input.pauseReason,
    pauseReasonCode: input.pauseReasonCode,
    recommendedAction: input.recommendedAction,
    scannedCount: input.scannedCount ?? 0,
    blockedCount: input.blockedCount ?? 0,
    skippedCount: input.skippedCount ?? 0,
    highestSafetyMode: safetyModeForPhase(input.phase),
    telemetry: input.telemetry
  };
}

function continueResult(input: {
  phase: AutonomyRunPhase;
  requiredAction: AutonomyRequiredAction;
  selectedUnitKeys: string[];
  maxUnitsApplied: number;
  maxRowsApplied: number;
  highestSafetyMode: EvaluateAutonomyCycleResult["highestSafetyMode"];
  scannedCount: number;
  skippedCount?: number;
  recommendedAction?: AutonomyRecommendedAction;
  telemetry: AutonomyCycleTelemetryPayload;
}): EvaluateAutonomyCycleResult {
  return {
    decision: "continue",
    phase: input.phase,
    selectedUnitKeys: input.selectedUnitKeys,
    maxUnitsApplied: input.maxUnitsApplied,
    maxRowsApplied: input.maxRowsApplied,
    requiredAction: input.requiredAction,
    recommendedAction: input.recommendedAction,
    scannedCount: input.scannedCount,
    blockedCount: 0,
    skippedCount: input.skippedCount ?? 0,
    highestSafetyMode: input.highestSafetyMode,
    telemetry: input.telemetry
  };
}

function safetyModeForPhase(phase: AutonomyRunPhase): EvaluateAutonomyCycleResult["highestSafetyMode"] {
  if (phase === "staging_canary") return "staging_write";
  if (phase === "production_inbox") return "production_write";
  return "dry_run";
}
