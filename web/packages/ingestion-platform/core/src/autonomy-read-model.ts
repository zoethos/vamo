/**
 * Autonomy dashboard read model — pure transforms for IP-18.7.
 *
 * Maps policy/run rows plus evaluateAutonomyCycle output into a dashboard view.
 * No DB, network, or provider calls.
 */

import {
  evaluateAutonomyCycle,
  type AutonomyPolicyEnvelope,
  type AutonomyProductionPackageState,
  type AutonomyRollingCounts,
  type EvaluateAutonomyCycleResult
} from "./autonomy-policy.js";
import type { AutonomyRunPhase, AutonomyRunStatus } from "./control-models.js";
import type {
  BatchQueueLatestExecution,
  BatchQueueLatestWave,
  BatchQueueSnapshot
} from "./batch-queue-read-model.js";
import { sampleVamoEuPoiBatchQueueSnapshot } from "./batch-queue-read-model.js";

export interface AutonomyPolicySummary {
  policyId: string;
  policyKey: string;
  status: string;
  sourceKey: string;
  targetKey: string;
  targetEnvironment: string;
  policyVersion: number;
  maxUnitsPerCycle: number;
  maxRowsPerCycle: number;
  approvedBy?: string;
  approvedAuditId?: string;
  approvalReason?: string;
  summary?: Record<string, unknown>;
  updatedAt?: string;
}

export interface AutonomyRunSummary {
  runKey: string;
  phase: AutonomyRunPhase;
  status: AutonomyRunStatus;
  actorType: string;
  actorId: string;
  selectedUnitKeys: string[];
  scannedCount: number;
  advancedCount: number;
  blockedCount: number;
  skippedCount: number;
  pauseReason?: string;
  recommendedAction?: Record<string, unknown>;
  dryRunExecutionKey?: string;
  waveKey?: string;
  packageKey?: string;
  startedAt?: string;
  completedAt?: string;
  createdAt?: string;
}

export interface AutonomyDashboardView {
  projectKey: string;
  policy: AutonomyPolicySummary | null;
  latestRun: AutonomyRunSummary | null;
  nextCycle: EvaluateAutonomyCycleResult;
  evidence: {
    dryRunExecution?: BatchQueueLatestExecution | null;
    stagingWave?: BatchQueueLatestWave | null;
    productionPackage?: AutonomyProductionPackageState | null;
  };
  safetySummary: string[];
}

export interface BuildAutonomyDashboardViewInput {
  projectKey: string;
  policy: AutonomyPolicyEnvelope | null;
  latestRun?: AutonomyRunSummary | null;
  queueSnapshot?: BatchQueueSnapshot | null;
  latestDryRunExecution?: BatchQueueLatestExecution | null;
  latestStagingWave?: BatchQueueLatestWave | null;
  productionPackage?: AutonomyProductionPackageState | null;
  rollingCounts?: AutonomyRollingCounts;
  externalBlockers?: string[];
  actor?: { type: "autonomous_agent"; id: string };
}

const FOUNDATION_SAFETY_SUMMARY = [
  "IP-18.7.0 foundation only — no live executor in this slice.",
  "No provider calls. No Vamo staging writes. No production inbox writes.",
  "Agent authority is limited to an active policy envelope plus existing guards.",
  "Target environment is explicit — never inferred from target key text."
] as const;

export function buildAutonomyDashboardView(
  input: BuildAutonomyDashboardViewInput
): AutonomyDashboardView {
  const actor = input.actor ?? { type: "autonomous_agent" as const, id: "confluendo-autonomy-preview" };
  const queueSnapshot = input.queueSnapshot ?? null;

  const nextCycle = evaluateAutonomyCycle({
    policy: input.policy,
    queueSnapshot,
    latestDryRunExecution: input.latestDryRunExecution,
    latestStagingWave: input.latestStagingWave,
    productionPackage: input.productionPackage,
    rollingCounts: input.rollingCounts,
    externalBlockers: input.externalBlockers,
    actor
  });

  return {
    projectKey: input.projectKey,
    policy: input.policy ? toPolicySummary(input.policy) : null,
    latestRun: input.latestRun ?? null,
    nextCycle,
    evidence: {
      dryRunExecution: input.latestDryRunExecution ?? queueSnapshot?.latestExecution ?? null,
      stagingWave: input.latestStagingWave ?? queueSnapshot?.latestWave ?? null,
      productionPackage: input.productionPackage ?? null
    },
    safetySummary: [...FOUNDATION_SAFETY_SUMMARY]
  };
}

export function mapPersistedPolicyRow(row: {
  id: string;
  policyKey: string;
  projectKey: string;
  sourceKey: string;
  targetKey: string;
  targetEnvironment: "staging" | "production";
  status: AutonomyPolicyEnvelope["status"];
  allowedTiers: unknown;
  allowedGeographies: unknown;
  allowedCategories: unknown;
  allowedTransitions: unknown;
  maxUnitsPerCycle: number;
  maxRowsPerCycle: number;
  rollingLimits: Record<string, unknown>;
  guardThresholds: Record<string, unknown>;
  productionInboxHandoffPolicy: Record<string, unknown>;
  policyVersion: number;
  approvedBy?: string | null;
  approvedAuditId?: string | null;
  approvalReason?: string | null;
  summary?: Record<string, unknown> | null;
  updatedAt?: string | Date | null;
}): AutonomyPolicyEnvelope {
  return {
    policyId: row.id,
    policyKey: row.policyKey,
    projectKey: row.projectKey,
    sourceKey: row.sourceKey,
    targetKey: row.targetKey,
    targetEnvironment: row.targetEnvironment,
    status: row.status,
    allowedTiers: readStringArray(row.allowedTiers),
    allowedGeographies: readStringArray(row.allowedGeographies),
    allowedCategories: readStringArray(row.allowedCategories),
    allowedTransitions: readStringArray(row.allowedTransitions),
    maxUnitsPerCycle: row.maxUnitsPerCycle,
    maxRowsPerCycle: row.maxRowsPerCycle,
    rollingLimits: row.rollingLimits ?? {},
    guardThresholds: row.guardThresholds ?? {},
    productionInboxHandoffPolicy: row.productionInboxHandoffPolicy ?? {},
    policyVersion: row.policyVersion,
    approvedBy: row.approvedBy ?? undefined,
    approvedAuditId: row.approvedAuditId ?? undefined,
    approvalReason: row.approvalReason ?? undefined,
    summary: row.summary ?? undefined
  };
}

export function mapPersistedRunRow(row: {
  runKey: string;
  phase: AutonomyRunPhase;
  status: AutonomyRunStatus;
  actorType: string;
  actorId: string;
  selectedUnits: unknown;
  scannedCount: number;
  advancedCount: number;
  blockedCount: number;
  skippedCount: number;
  pauseReason?: string | null;
  recommendedAction?: Record<string, unknown> | null;
  dryRunExecutionKey?: string | null;
  waveKey?: string | null;
  packageKey?: string | null;
  startedAt?: string | Date | null;
  completedAt?: string | Date | null;
  createdAt?: string | Date | null;
}): AutonomyRunSummary {
  return {
    runKey: row.runKey,
    phase: row.phase,
    status: row.status,
    actorType: row.actorType,
    actorId: row.actorId,
    selectedUnitKeys: readStringArray(row.selectedUnits),
    scannedCount: row.scannedCount,
    advancedCount: row.advancedCount,
    blockedCount: row.blockedCount,
    skippedCount: row.skippedCount,
    pauseReason: row.pauseReason ?? undefined,
    recommendedAction: row.recommendedAction ?? undefined,
    dryRunExecutionKey: row.dryRunExecutionKey ?? undefined,
    waveKey: row.waveKey ?? undefined,
    packageKey: row.packageKey ?? undefined,
    startedAt: toIso(row.startedAt),
    completedAt: toIso(row.completedAt),
    createdAt: toIso(row.createdAt)
  };
}

export function sampleVamoAutonomyDashboardView(): AutonomyDashboardView {
  const queueSnapshot = sampleVamoEuPoiBatchQueueSnapshot();
  const policy: AutonomyPolicyEnvelope = {
    policyId: "sample-policy",
    policyKey: "vamo-eu-poi-staging",
    projectKey: "vamo",
    sourceKey: queueSnapshot.sourceKey,
    targetKey: queueSnapshot.targetKey,
    targetEnvironment: "staging",
    status: "active",
    allowedTiers: ["sample_dry_run", "staging_canary"],
    allowedGeographies: ["fr", "es", "de"],
    allowedCategories: ["city", "poi"],
    allowedTransitions: ["schedule_dry_run", "execute_dry_run", "approve_staging_wave"],
    maxUnitsPerCycle: 2,
    maxRowsPerCycle: 500,
    rollingLimits: { maxCyclesPerDay: 12 },
    guardThresholds: { maxBlockerRate: 0.1 },
    productionInboxHandoffPolicy: { requiresIp186: true },
    policyVersion: 1,
    approvedBy: "operator@example.com",
    approvedAuditId: "sample-approval",
    approvalReason: "Sample autonomy envelope for dashboard preview.",
    summary: { note: "Bundled sample — not live control-plane data." }
  };

  const previewQueue: BatchQueueSnapshot = {
    ...queueSnapshot,
    items: queueSnapshot.items.map((item, index) =>
      index < 2
        ? { ...item, status: "dry_run_ready" as const }
        : item
    )
  };

  return buildAutonomyDashboardView({
    projectKey: "vamo",
    policy,
    queueSnapshot: previewQueue,
    actor: { type: "autonomous_agent", id: "confluendo-autonomy-preview" }
  });
}

function toPolicySummary(policy: AutonomyPolicyEnvelope): AutonomyPolicySummary {
  return {
    policyId: policy.policyId,
    policyKey: policy.policyKey,
    status: policy.status,
    sourceKey: policy.sourceKey,
    targetKey: policy.targetKey,
    targetEnvironment: policy.targetEnvironment,
    policyVersion: policy.policyVersion,
    maxUnitsPerCycle: policy.maxUnitsPerCycle,
    maxRowsPerCycle: policy.maxRowsPerCycle,
    approvedBy: policy.approvedBy,
    approvedAuditId: policy.approvedAuditId,
    approvalReason: policy.approvalReason,
    summary: policy.summary
  };
}

function readStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.filter((entry): entry is string => typeof entry === "string");
}

function toIso(value: string | Date | null | undefined): string | undefined {
  if (value instanceof Date) return value.toISOString();
  return typeof value === "string" ? value : undefined;
}
