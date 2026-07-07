/**
 * Pure production package-wave delivery policy (IP-18.6.3).
 *
 * Selects an approved wave for confirmation-gated production inbox delivery.
 * No DB, network, provider, or consumer target access.
 */

import {
  evaluateProductionPackageWaveDeliveryDrift,
  isApprovedProductionPackageWaveFresh,
  VAMO_PRODUCTION_PACKAGE_SCHEMA_CONTRACT,
  type ProductionPackageDryRunEvidence,
  type ProductionPackageStagingEvidence
} from "./batch-production-package-wave-policy.js";
import type { BatchQueueItem } from "./batch-queue-read-model.js";
import type {
  LoadedProductionPackageWave,
  LoadedProductionPackageWaveItem
} from "./batch-production-package-wave-load.js";

export type BatchProductionPackageWaveDeliveryBlockCode =
  | "wave_not_found"
  | "wave_not_deliverable"
  | "approval_expired"
  | "not_production_environment"
  | "schema_contract_mismatch"
  | "already_delivered"
  | "consumer_already_applied"
  | "max_units_invalid"
  | "max_rows_invalid"
  | "max_packages_invalid"
  | "approved_wave_bounds_exceeded"
  | "no_pending_items"
  | "package_key_missing"
  | "checksum_incompatible"
  | "queue_status_drift"
  | "dry_run_evidence_drift"
  | "staging_evidence_drift"
  | "schema_contract_drift"
  | "active_blockers";

export interface BatchProductionPackageWaveDeliveryBlock {
  code: BatchProductionPackageWaveDeliveryBlockCode;
  message: string;
}

export interface BatchProductionPackageWaveDeliveryUnitPlan {
  waveItemId: string;
  unitKey: string;
  runOrder: number;
  plannedRowCount: number;
  packageKey: string;
  status: "pending" | "skip_delivered";
  storedPackageId?: string | null;
  storedChecksum?: string | null;
}

export interface BatchProductionPackageWaveDeliveryPlan {
  action: "deliver_batch_production_package_wave";
  projectKey: string;
  waveId: string;
  waveKey: string;
  planKey: string;
  targetKey: string;
  targetEnvironment: "production";
  schemaContract: typeof VAMO_PRODUCTION_PACKAGE_SCHEMA_CONTRACT;
  approvalAuditId: string | null;
  maxUnits: number;
  maxRows: number;
  maxPackages: number;
  unitPlans: BatchProductionPackageWaveDeliveryUnitPlan[];
  pendingUnitKeys: string[];
  safetySummary: string[];
}

export type EvaluateBatchProductionPackageWaveDeliveryResult =
  | { ok: true; plan: BatchProductionPackageWaveDeliveryPlan }
  | { ok: false; blocks: BatchProductionPackageWaveDeliveryBlock[] };

export interface EvaluateBatchProductionPackageWaveDeliveryInput {
  projectKey: string;
  targetEnvironment: string;
  wave: LoadedProductionPackageWave | null;
  queueItemsByUnitKey: Readonly<Record<string, BatchQueueItem>>;
  stagingEvidenceByUnitKey?: Readonly<Record<string, ProductionPackageStagingEvidence>>;
  maxUnits?: number;
  maxRows?: number;
  maxPackages?: number;
  now?: string;
}

const DELIVERABLE_WAVE_STATUSES = new Set(["approved", "delivering"]);
const PENDING_ITEM_STATUSES = new Set(["approved", "delivering"]);
const DELIVERED_ITEM_STATUSES = new Set(["delivered", "consumer_apply_pending", "consumer_applied"]);
const TERMINAL_WAVE_STATUSES = new Set([
  "delivered",
  "consumer_apply_pending",
  "consumer_applied",
  "consumer_apply_failed",
  "expired",
  "blocked"
]);

const DEFAULT_SAFETY_SUMMARY = [
  "Reuses IP-17 buildProductionInboxPackage and deliverPostgresProductionInboxPackage only.",
  "Writes to Vamo production confluendo_inbox only when explicitly confirmed.",
  "No Vamo product-table apply in this action.",
  "Checksum authority remains in consumer Postgres.",
  "Execute requires CONFIRM_CONFLUENDO_PRODUCTION_PACKAGE_WAVE=YES and production inbox DSN."
] as const;

export function evaluateBatchProductionPackageWaveDelivery(
  input: EvaluateBatchProductionPackageWaveDeliveryInput
): EvaluateBatchProductionPackageWaveDeliveryResult {
  const blocks: BatchProductionPackageWaveDeliveryBlock[] = [];
  const now = input.now ?? new Date().toISOString();

  if (!input.wave) {
    blocks.push({
      code: "wave_not_found",
      message: "No production package wave matched the requested wave key or approval audit id."
    });
    return { ok: false, blocks };
  }

  if (input.targetEnvironment !== "production") {
    blocks.push({
      code: "not_production_environment",
      message: `Production package-wave delivery requires targetEnvironment=production, not "${input.targetEnvironment}".`
    });
  }

  if (input.wave.schemaContract !== VAMO_PRODUCTION_PACKAGE_SCHEMA_CONTRACT) {
    blocks.push({
      code: "schema_contract_mismatch",
      message: `Schema contract must be ${VAMO_PRODUCTION_PACKAGE_SCHEMA_CONTRACT}, not "${input.wave.schemaContract}".`
    });
  }

  if (input.wave.status === "expired") {
    blocks.push({
      code: "approval_expired",
      message: "The production package-wave approval has expired and was released."
    });
  } else if (TERMINAL_WAVE_STATUSES.has(input.wave.status) && input.wave.status !== "delivered") {
    if (input.wave.status === "consumer_applied") {
      blocks.push({
        code: "consumer_already_applied",
        message: "The production package wave has already been consumer-applied."
      });
    } else {
      blocks.push({
        code: "wave_not_deliverable",
        message: `Wave status "${input.wave.status}" is not deliverable.`
      });
    }
  } else if (!DELIVERABLE_WAVE_STATUSES.has(input.wave.status) && input.wave.status !== "delivered") {
    blocks.push({
      code: "wave_not_deliverable",
      message: `Wave status "${input.wave.status}" is not deliverable (need approved/delivering).`
    });
  }

  if (
    DELIVERABLE_WAVE_STATUSES.has(input.wave.status) &&
    !isApprovedProductionPackageWaveFresh({
      approvedAt: input.wave.approvedAt,
      now
    })
  ) {
    blocks.push({
      code: "approval_expired",
      message: "The production package-wave approval freshness window has expired."
    });
  }

  const maxUnits = input.maxUnits ?? input.wave.maxUnits;
  const maxRows = input.maxRows ?? input.wave.maxRows;
  const maxPackages = input.maxPackages ?? input.wave.maxPackages;

  if (!Number.isFinite(maxUnits) || maxUnits < 1) {
    blocks.push({ code: "max_units_invalid", message: "maxUnits must be a positive integer." });
  }
  if (!Number.isFinite(maxRows) || maxRows < 1) {
    blocks.push({ code: "max_rows_invalid", message: "maxRows must be a positive integer." });
  }
  if (!Number.isFinite(maxPackages) || maxPackages < 1) {
    blocks.push({ code: "max_packages_invalid", message: "maxPackages must be a positive integer." });
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
  if (Number.isFinite(maxPackages) && maxPackages > input.wave.maxPackages) {
    blocks.push({
      code: "approved_wave_bounds_exceeded",
      message: `Requested maxPackages (${maxPackages}) exceeds the approved wave bound (${input.wave.maxPackages}).`
    });
  }

  if (blocks.length > 0) {
    return { ok: false, blocks };
  }

  const unitPlans = buildUnitPlans(input.wave, maxUnits, maxRows, maxPackages);
  const driftBlocks = collectDriftBlocks(input.wave.items, unitPlans, {
    queueItemsByUnitKey: input.queueItemsByUnitKey,
    stagingEvidenceByUnitKey: input.stagingEvidenceByUnitKey ?? {},
    schemaContract: input.wave.schemaContract
  });
  if (driftBlocks.length > 0) {
    return { ok: false, blocks: driftBlocks };
  }

  const pending = unitPlans.filter((plan) => plan.status === "pending");
  if (pending.length === 0 && input.wave.status !== "delivered") {
    blocks.push({
      code: "no_pending_items",
      message: "There are no approved production package-wave items pending delivery."
    });
    return { ok: false, blocks };
  }

  if (input.wave.status === "delivered" && pending.length === 0) {
    return {
      ok: true,
      plan: toDeliveryPlan(input, maxUnits, maxRows, maxPackages, unitPlans, [])
    };
  }

  return {
    ok: true,
    plan: toDeliveryPlan(
      input,
      maxUnits,
      maxRows,
      maxPackages,
      unitPlans,
      pending.map((plan) => plan.unitKey)
    )
  };
}

function buildUnitPlans(
  wave: LoadedProductionPackageWave,
  maxUnits: number,
  maxRows: number,
  maxPackages: number
): BatchProductionPackageWaveDeliveryUnitPlan[] {
  const plans: BatchProductionPackageWaveDeliveryUnitPlan[] = [];
  let selectedUnits = 0;
  let selectedRows = 0;

  for (const item of wave.items.sort((a, b) => a.runOrder - b.runOrder)) {
    if (DELIVERED_ITEM_STATUSES.has(item.status)) {
      plans.push(toUnitPlan(item, "skip_delivered"));
      continue;
    }
    if (!PENDING_ITEM_STATUSES.has(item.status)) {
      continue;
    }
    if (selectedUnits >= maxUnits || selectedUnits >= maxPackages) {
      break;
    }
    if (selectedRows + item.plannedRowCount > maxRows) {
      break;
    }
    plans.push(toUnitPlan(item, "pending"));
    selectedUnits += 1;
    selectedRows += item.plannedRowCount;
  }

  return plans;
}

function toUnitPlan(
  item: LoadedProductionPackageWaveItem,
  status: BatchProductionPackageWaveDeliveryUnitPlan["status"]
): BatchProductionPackageWaveDeliveryUnitPlan {
  const packageKey = item.packageKey?.trim();
  if (!packageKey && status === "pending") {
    throw new Error(`Wave item "${item.unitKey}" is missing a planned package key.`);
  }
  return {
    waveItemId: item.id,
    unitKey: item.unitKey,
    runOrder: item.runOrder,
    plannedRowCount: item.plannedRowCount,
    packageKey: packageKey ?? "",
    status,
    storedPackageId: item.packageId,
    storedChecksum: item.checksum
  };
}

function collectDriftBlocks(
  waveItems: LoadedProductionPackageWaveItem[],
  unitPlans: BatchProductionPackageWaveDeliveryUnitPlan[],
  input: {
    queueItemsByUnitKey: Readonly<Record<string, BatchQueueItem>>;
    stagingEvidenceByUnitKey: Readonly<Record<string, ProductionPackageStagingEvidence>>;
    schemaContract: string;
  }
): BatchProductionPackageWaveDeliveryBlock[] {
  const blocks: BatchProductionPackageWaveDeliveryBlock[] = [];
  const waveItemById = new Map(waveItems.map((item) => [item.id, item]));

  for (const plan of unitPlans) {
    if (plan.status !== "pending") {
      continue;
    }
    if (!plan.packageKey) {
      blocks.push({
        code: "package_key_missing",
        message: `Unit "${plan.unitKey}" is missing a package key.`
      });
      continue;
    }

    const waveItem = waveItemById.get(plan.waveItemId);
    if (!waveItem) {
      continue;
    }

    const currentItem = input.queueItemsByUnitKey[plan.unitKey] ?? null;
    const drift = evaluateProductionPackageWaveDeliveryDrift({
      approvedUnit: {
        item: currentItem ?? {
          unitKey: plan.unitKey,
          runOrder: plan.runOrder,
          geography: "",
          geographyKind: "city",
          country: "",
          category: "",
          targetKey: "",
          targetEnvironment: "production",
          sourceKey: "",
          priority: 0,
          status: "production_package_approved",
          blockReasons: [],
          dryRunReport: null
        },
        dryRunEvidence: waveItem.dryRunEvidence as ProductionPackageDryRunEvidence,
        stagingEvidence: waveItem.stagingEvidence,
        writeCount: waveItem.plannedRowCount,
        plannedPackageKey: plan.packageKey
      },
      currentItem,
      currentStagingEvidence: input.stagingEvidenceByUnitKey[plan.unitKey] ?? null,
      expectedSchemaContract: input.schemaContract,
      storedChecksum: plan.storedChecksum,
      incomingChecksum: plan.storedChecksum
    });

    for (const driftBlock of drift) {
      blocks.push({
        code: driftBlock.code as BatchProductionPackageWaveDeliveryBlockCode,
        message: driftBlock.message
      });
    }
  }

  return blocks;
}

function toDeliveryPlan(
  input: EvaluateBatchProductionPackageWaveDeliveryInput,
  maxUnits: number,
  maxRows: number,
  maxPackages: number,
  unitPlans: BatchProductionPackageWaveDeliveryUnitPlan[],
  pendingUnitKeys: string[]
): BatchProductionPackageWaveDeliveryPlan {
  const wave = input.wave!;
  return {
    action: "deliver_batch_production_package_wave",
    projectKey: input.projectKey,
    waveId: wave.id,
    waveKey: wave.waveKey,
    planKey: wave.planKey,
    targetKey: wave.targetKey,
    targetEnvironment: "production",
    schemaContract: VAMO_PRODUCTION_PACKAGE_SCHEMA_CONTRACT,
    approvalAuditId: wave.approvalAuditId,
    maxUnits,
    maxRows,
    maxPackages,
    unitPlans,
    pendingUnitKeys,
    safetySummary: [...DEFAULT_SAFETY_SUMMARY]
  };
}
