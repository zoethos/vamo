/**
 * Pure production package-wave policy (IP-18.6.1).
 *
 * Selects staging-proven units for production inbox package waves and validates
 * operator approval gates. No DB, network, provider, or consumer target access.
 */

import {
  ADMIN_FRESH_STEP_UP_CLOCK_SKEW_MS,
  type AdminPrincipal
} from "./admin-auth.js";
import type { BatchDryRunReport, BatchQueueItem, BatchQueueSnapshot } from "./batch-queue-read-model.js";
import {
  PRODUCTION_INBOX_APPROVAL_MAX_AGE_MS,
  PRODUCTION_INBOX_FRESH_STEP_UP_WINDOW_MS,
  isProductionInboxApprovalFresh
} from "./production-inbox-policy.js";

export const VAMO_PRODUCTION_PACKAGE_SCHEMA_CONTRACT = "vamo-place-intelligence@1" as const;

export type ProductionPackageSchemaContract = typeof VAMO_PRODUCTION_PACKAGE_SCHEMA_CONTRACT;

export type BatchProductionPackageWaveBlockCode =
  | "not_staging_proven"
  | "not_production_environment"
  | "legacy_target_key"
  | "schema_contract_mismatch"
  | "dry_run_invariant_violated"
  | "staging_canary_required"
  | "staging_canary_not_succeeded"
  | "active_blockers"
  | "delete_not_allowed"
  | "row_bound_exceeded"
  | "unit_bound_exceeded"
  | "package_bound_exceeded"
  | "already_delivered_or_pending_apply"
  | "approval_expired"
  | "role_denied"
  | "scope_denied"
  | "mfa_required"
  | "fresh_step_up_required"
  | "audit_reason_required"
  | "max_units_invalid"
  | "max_rows_invalid"
  | "max_packages_invalid"
  | "first_wave_ramp_exceeded"
  | "no_eligible_items"
  | "queue_status_drift"
  | "dry_run_evidence_drift"
  | "staging_evidence_drift"
  | "schema_contract_drift"
  | "checksum_incompatible"
  | "staged_content_drift"
  | "staged_content_hash_missing"
  | "unit_key_not_found"
  | "unit_target_mismatch"
  | "unit_selection_exceeds_max_units";

export interface BatchProductionPackageWaveBlock {
  code: BatchProductionPackageWaveBlockCode;
  message: string;
}

export interface ProductionPackageDryRunEvidence {
  executionKey?: string;
  wroteToTarget: false;
  insertCount: number;
  updateCount: number;
  deleteCount?: number;
  rowsProcessed?: number;
  queueItemStatusAtApproval?: string;
}

export interface ProductionPackageStagingEvidence {
  status: string;
  shipmentKey?: string;
  shipmentId?: string;
  checksum?: string;
  stagedContentHash?: string;
  deliveryContentHash?: string;
}

export interface ProductionPackageWaveUnitSelectionIssue {
  unitKey: string;
  code: BatchProductionPackageWaveBlockCode;
  message: string;
}

export interface ProductionPackageWaveSelectedUnit {
  item: BatchQueueItem;
  dryRunEvidence: ProductionPackageDryRunEvidence;
  stagingEvidence: ProductionPackageStagingEvidence;
  writeCount: number;
  plannedPackageKey: string;
}

export interface BatchProductionPackageWaveApprovalPlan {
  action: "approve_batch_production_package_wave";
  waveKey: string;
  projectKey: string;
  queueId: string;
  planId: string;
  targetKey: string;
  targetEnvironment: "production";
  schemaContract: ProductionPackageSchemaContract;
  maxUnits: number;
  maxRows: number;
  maxPackages: number;
  unitKeys: string[];
  selectedUnits: ProductionPackageWaveSelectedUnit[];
  totalPlannedRows: number;
  auditReason: string;
  approvedAt: string;
  approvalExpiresAt: string;
  approvedBy: {
    email: string;
    role: AdminPrincipal["role"] | "autonomous_agent";
    assuranceLevel: AdminPrincipal["assuranceLevel"] | "policy";
    policyApprovedBy?: string | null;
    policyApprovalAuditId?: string | null;
  };
  safetySummary: string[];
}

export type EvaluateProductionPackageWaveEligibilityResult =
  | { ok: true; selectedUnits: ProductionPackageWaveSelectedUnit[]; totalPlannedRows: number }
  | {
      ok: false;
      blocks: BatchProductionPackageWaveBlock[];
      unitIssues?: ProductionPackageWaveUnitSelectionIssue[];
    };

export type EvaluateProductionPackageWaveApprovalResult =
  | { ok: true; plan: BatchProductionPackageWaveApprovalPlan; warnings: BatchProductionPackageWaveBlock[] }
  | {
      ok: false;
      blocks: BatchProductionPackageWaveBlock[];
      unitIssues?: ProductionPackageWaveUnitSelectionIssue[];
    };

export interface EvaluateProductionPackageWaveEligibilityInput {
  snapshot: BatchQueueSnapshot;
  targetKey: string;
  targetEnvironment: string;
  schemaContract: string;
  maxUnits: number;
  maxRows: number;
  maxPackages: number;
  stagingEvidenceByUnitKey: Readonly<Record<string, ProductionPackageStagingEvidence>>;
  occupiedUnitKeys?: ReadonlySet<string>;
  hasPriorDeliveredPackage?: boolean;
  unitKeys?: readonly string[];
}

export interface EvaluateProductionPackageWaveApprovalInput {
  projectKey: string;
  snapshot: BatchQueueSnapshot;
  principal: AdminPrincipal;
  targetKey: string;
  targetEnvironment: string;
  schemaContract: string;
  maxUnits: number;
  maxRows: number;
  maxPackages: number;
  auditReason: string;
  stagingEvidenceByUnitKey: Readonly<Record<string, ProductionPackageStagingEvidence>>;
  occupiedUnitKeys?: ReadonlySet<string>;
  hasPriorDeliveredPackage?: boolean;
  unitKeys?: readonly string[];
  now?: string;
}

export interface EvaluateProductionPackageWaveDeliveryDriftInput {
  approvedUnit: ProductionPackageWaveSelectedUnit;
  currentItem: BatchQueueItem | null;
  currentStagingEvidence?: ProductionPackageStagingEvidence | null;
  expectedSchemaContract: string;
  storedChecksum?: string | null;
  incomingChecksum?: string | null;
}

const DEFAULT_SAFETY_SUMMARY = [
  "Control-plane package-wave approval only.",
  "No production inbox delivery in this action.",
  "No Vamo product-table writes.",
  "Delivery requires a separate confirmation-gated runbook step (IP-18.6.3)."
] as const;

const FIRST_WAVE_MAX_UNITS = 1;
const FIRST_WAVE_MAX_PACKAGES = 1;
const SUCCEEDED_STAGING_STATUSES = new Set(["succeeded"]);
const OCCUPIED_PACKAGE_ITEM_STATUSES = new Set([
  "production_package_approved",
  "production_package_delivering",
  "production_package_delivered",
  "consumer_apply_pending",
  "consumer_applied",
  "consumer_apply_failed"
]);

export function buildProductionPackageWaveKey(
  planKey: string,
  approvalAuditId: string,
  unitKey: string
): string {
  return `batch-production-inbox:${planKey}:wave:${approvalAuditId}:unit:${unitKey}`;
}

export function finalizeProductionPackageWaveApprovalPlan(
  plan: BatchProductionPackageWaveApprovalPlan,
  approvalAuditId: string
): BatchProductionPackageWaveApprovalPlan {
  const primaryUnitKey = plan.unitKeys[0] ?? "none";
  const waveKey = buildProductionPackageWaveKey(plan.planId, approvalAuditId, primaryUnitKey);
  return {
    ...plan,
    waveKey,
    selectedUnits: plan.selectedUnits.map((entry) => ({
      ...entry,
      plannedPackageKey: buildProductionPackageWaveKey(
        plan.planId,
        approvalAuditId,
        entry.item.unitKey
      )
    }))
  };
}

export function countStagingProvenPackageEligibleUnits(
  snapshot: BatchQueueSnapshot,
  targetKey: string,
  stagingEvidenceByUnitKey: Readonly<Record<string, ProductionPackageStagingEvidence>>
): number {
  return snapshot.items.filter((item) => {
    if (item.status !== "staging_canary_succeeded" || item.targetKey !== targetKey) {
      return false;
    }
    if (item.blockReasons.length > 0) {
      return false;
    }
    const staging = stagingEvidenceByUnitKey[item.unitKey];
    if (!staging || !SUCCEEDED_STAGING_STATUSES.has(staging.status)) {
      return false;
    }
    return item.dryRunReport?.wroteToTarget === false;
  }).length;
}

export function isLegacyProductionTargetKey(targetKey: string): boolean {
  const trimmed = targetKey.trim();
  return trimmed.endsWith("-staging") || trimmed.includes("-staging-");
}

export function evaluateProductionPackageWaveEligibility(
  input: EvaluateProductionPackageWaveEligibilityInput
): EvaluateProductionPackageWaveEligibilityResult {
  const blocks: BatchProductionPackageWaveBlock[] = [];

  if (input.targetEnvironment !== "production") {
    blocks.push({
      code: "not_production_environment",
      message: `Production package waves require targetEnvironment=production, not "${input.targetEnvironment}".`
    });
  }

  if (isLegacyProductionTargetKey(input.targetKey)) {
    blocks.push({
      code: "legacy_target_key",
      message: `Target key "${input.targetKey}" looks legacy/environment-suffixed; use an environment-neutral key.`
    });
  }

  if (input.schemaContract !== VAMO_PRODUCTION_PACKAGE_SCHEMA_CONTRACT) {
    blocks.push({
      code: "schema_contract_mismatch",
      message: `Schema contract must be ${VAMO_PRODUCTION_PACKAGE_SCHEMA_CONTRACT}, not "${input.schemaContract}".`
    });
  }

  if (!Number.isFinite(input.maxUnits) || input.maxUnits < 1) {
    blocks.push({
      code: "max_units_invalid",
      message: "maxUnits must be a positive integer."
    });
  }

  if (!Number.isFinite(input.maxRows) || input.maxRows < 1) {
    blocks.push({
      code: "max_rows_invalid",
      message: "maxRows must be a positive integer."
    });
  }

  if (!Number.isFinite(input.maxPackages) || input.maxPackages < 1) {
    blocks.push({
      code: "max_packages_invalid",
      message: "maxPackages must be a positive integer."
    });
  }

  const hasPriorDelivered = input.hasPriorDeliveredPackage === true;
  if (!hasPriorDelivered && input.maxUnits > FIRST_WAVE_MAX_UNITS) {
    blocks.push({
      code: "first_wave_ramp_exceeded",
      message: "The first live production package wave is hard-capped at 1 unit."
    });
  }
  if (!hasPriorDelivered && input.maxPackages > FIRST_WAVE_MAX_PACKAGES) {
    blocks.push({
      code: "package_bound_exceeded",
      message: "The first live production package wave is hard-capped at 1 package."
    });
  }

  if (blocks.length > 0) {
    return { ok: false, blocks };
  }

  const occupied = input.occupiedUnitKeys ?? new Set<string>();
  const hintedUnitKeys = normalizeUnitKeyHints(input.unitKeys);
  if (hintedUnitKeys.length > 0) {
    return finalizeExplicitProductionUnitSelection({
      input,
      hintedUnitKeys,
      occupied
    });
  }

  const candidates = input.snapshot.items
    .filter((item) => item.status === "staging_canary_succeeded")
    .filter((item) => item.targetKey === input.targetKey)
    .sort((a, b) => a.runOrder - b.runOrder);

  const selected: ProductionPackageWaveSelectedUnit[] = [];
  let totalPlannedRows = 0;
  let firstSkipBlock: BatchProductionPackageWaveBlock | undefined;

  for (const item of candidates) {
    if (selected.length >= input.maxUnits) {
      break;
    }
    if (selected.length >= input.maxPackages) {
      break;
    }
    if (occupied.has(item.unitKey)) {
      firstSkipBlock ??= {
        code: "already_delivered_or_pending_apply",
        message: `Unit "${item.unitKey}" is already in an active or spent production package wave.`
      };
      continue;
    }

    const unitBlock = validateEligibleUnit(item, input.stagingEvidenceByUnitKey[item.unitKey]);
    if (unitBlock) {
      firstSkipBlock ??= unitBlock;
      continue;
    }

    const parsed = parseDryRunEvidence(item);
    const stagingEvidence = input.stagingEvidenceByUnitKey[item.unitKey]!;
    const writeCount = parsed.writeCount;

    if (totalPlannedRows + writeCount > input.maxRows) {
      break;
    }

    selected.push({
      item,
      dryRunEvidence: parsed.evidence,
      stagingEvidence,
      writeCount,
      plannedPackageKey: buildProductionPackageWaveKey(
        input.snapshot.planId,
        "pending",
        item.unitKey
      )
    });
    totalPlannedRows += writeCount;
  }

  if (selected.length === 0) {
    return {
      ok: false,
      blocks: [
        firstSkipBlock ?? {
          code: "no_eligible_items",
          message:
            "There are no staging_canary_succeeded units with valid dry-run and staging evidence within bounds."
        }
      ]
    };
  }

  if (selected.length > input.maxUnits) {
    return {
      ok: false,
      blocks: [
        {
          code: "unit_bound_exceeded",
          message: `Selected ${selected.length} units exceeds maxUnits (${input.maxUnits}).`
        }
      ]
    };
  }

  if (selected.length > input.maxPackages) {
    return {
      ok: false,
      blocks: [
        {
          code: "package_bound_exceeded",
          message: `Selected ${selected.length} packages exceeds maxPackages (${input.maxPackages}).`
        }
      ]
    };
  }

  if (totalPlannedRows > input.maxRows) {
    return {
      ok: false,
      blocks: [
        {
          code: "row_bound_exceeded",
          message: `Selected rows (${totalPlannedRows}) exceed maxRows (${input.maxRows}).`
        }
      ]
    };
  }

  return { ok: true, selectedUnits: selected, totalPlannedRows };
}

export function evaluateProductionPackageWaveApproval(
  input: EvaluateProductionPackageWaveApprovalInput
): EvaluateProductionPackageWaveApprovalResult {
  const blocks: BatchProductionPackageWaveBlock[] = [];
  const warnings: BatchProductionPackageWaveBlock[] = [];
  const auditReason = input.auditReason.trim();
  const now = input.now ?? new Date().toISOString();

  if (input.principal.role !== "admin") {
    blocks.push({
      code: "role_denied",
      message: "Production package-wave approval requires an ingestion_admin (role=admin) principal."
    });
  }

  if (!principalHasProjectScope(input.principal, input.projectKey)) {
    blocks.push({
      code: "scope_denied",
      message: "The operator is not scoped to this ingestion project."
    });
  }

  if (
    input.principal.assuranceLevel !== "aal2" ||
    (input.principal.mfaRequired && !input.principal.hasVerifiedMfaFactor)
  ) {
    blocks.push({
      code: "mfa_required",
      message: "Production package-wave approval requires verified MFA step-up (AAL2)."
    });
  }

  if (!hasFreshStepUp(input.principal, now)) {
    blocks.push({
      code: "fresh_step_up_required",
      message: "Production package-wave approval requires a fresh MFA step-up."
    });
  }

  if (!auditReason) {
    blocks.push({
      code: "audit_reason_required",
      message: "A non-empty audit reason is required to approve a production package wave."
    });
  }

  if (blocks.length > 0) {
    return { ok: false, blocks };
  }

  const eligibility = evaluateProductionPackageWaveEligibility({
    snapshot: input.snapshot,
    targetKey: input.targetKey,
    targetEnvironment: input.targetEnvironment,
    schemaContract: input.schemaContract,
    maxUnits: input.maxUnits,
    maxRows: input.maxRows,
    maxPackages: input.maxPackages,
    stagingEvidenceByUnitKey: input.stagingEvidenceByUnitKey,
    occupiedUnitKeys: input.occupiedUnitKeys,
    hasPriorDeliveredPackage: input.hasPriorDeliveredPackage,
    unitKeys: input.unitKeys
  });

  if (!eligibility.ok) {
    return { ok: false, blocks: eligibility.blocks, unitIssues: eligibility.unitIssues };
  }

  const unitKeys = eligibility.selectedUnits.map((entry) => entry.item.unitKey);
  const approvedAt = now;
  const approvalExpiresAt = new Date(
    Date.parse(approvedAt) + PRODUCTION_INBOX_APPROVAL_MAX_AGE_MS
  ).toISOString();

  const selectedUnits = eligibility.selectedUnits.map((entry) => ({
    ...entry,
    plannedPackageKey: ""
  }));

  return {
    ok: true,
    warnings,
    plan: {
      action: "approve_batch_production_package_wave",
      waveKey: "",
      projectKey: input.projectKey,
      queueId: input.snapshot.queueId,
      planId: input.snapshot.planId,
      targetKey: input.targetKey,
      targetEnvironment: "production",
      schemaContract: VAMO_PRODUCTION_PACKAGE_SCHEMA_CONTRACT,
      maxUnits: input.maxUnits,
      maxRows: input.maxRows,
      maxPackages: input.maxPackages,
      unitKeys,
      selectedUnits,
      totalPlannedRows: eligibility.totalPlannedRows,
      auditReason,
      approvedAt,
      approvalExpiresAt,
      approvedBy: {
        email: input.principal.email,
        role: input.principal.role,
        assuranceLevel: input.principal.assuranceLevel
      },
      safetySummary: [...DEFAULT_SAFETY_SUMMARY]
    }
  };
}

export function evaluateProductionPackageWaveDeliveryDrift(
  input: EvaluateProductionPackageWaveDeliveryDriftInput
): BatchProductionPackageWaveBlock[] {
  const blocks: BatchProductionPackageWaveBlock[] = [];
  const { approvedUnit, currentItem } = input;

  if (!currentItem) {
    blocks.push({
      code: "queue_status_drift",
      message: `Queue item for unit "${approvedUnit.item.unitKey}" is missing at delivery time.`
    });
    return blocks;
  }

  const approvedStatus = approvedUnit.dryRunEvidence.queueItemStatusAtApproval ?? "staging_canary_succeeded";
  if (currentItem.status !== approvedStatus && currentItem.status !== "production_package_approved") {
    const allowedProgression = new Set([
      "production_package_delivering",
      "production_package_delivered",
      "consumer_apply_pending",
      "consumer_applied"
    ]);
    if (!allowedProgression.has(currentItem.status)) {
      blocks.push({
        code: "queue_status_drift",
        message: `Unit "${currentItem.unitKey}" status drifted from "${approvedStatus}" to "${currentItem.status}".`
      });
    }
  }

  if (currentItem.blockReasons.length > 0) {
    blocks.push({
      code: "active_blockers",
      message: `Unit "${currentItem.unitKey}" has active blockers at delivery time.`
    });
  }

  const currentDryRun = parseDryRunEvidence(currentItem);
  if (currentDryRun.evidence.wroteToTarget !== false) {
    blocks.push({
      code: "dry_run_evidence_drift",
      message: `Unit "${currentItem.unitKey}" dry-run evidence no longer satisfies wroteToTarget=false.`
    });
  }

  if (
    currentDryRun.writeCount !== approvedUnit.writeCount ||
    currentDryRun.evidence.insertCount !== approvedUnit.dryRunEvidence.insertCount ||
    currentDryRun.evidence.updateCount !== approvedUnit.dryRunEvidence.updateCount
  ) {
    blocks.push({
      code: "dry_run_evidence_drift",
      message: `Unit "${currentItem.unitKey}" dry-run row counts drifted since approval.`
    });
  }

  if (input.currentStagingEvidence) {
    if (!SUCCEEDED_STAGING_STATUSES.has(input.currentStagingEvidence.status)) {
      blocks.push({
        code: "staging_evidence_drift",
        message: `Staging evidence for "${currentItem.unitKey}" is no longer succeeded.`
      });
    }
    if (
      approvedUnit.stagingEvidence.shipmentKey &&
      input.currentStagingEvidence.shipmentKey &&
      approvedUnit.stagingEvidence.shipmentKey !== input.currentStagingEvidence.shipmentKey
    ) {
      blocks.push({
        code: "staging_evidence_drift",
        message: `Staging shipment key drifted for unit "${currentItem.unitKey}".`
      });
    }
  }

  if (input.expectedSchemaContract !== VAMO_PRODUCTION_PACKAGE_SCHEMA_CONTRACT) {
    blocks.push({
      code: "schema_contract_drift",
      message: `Schema contract drift: expected ${VAMO_PRODUCTION_PACKAGE_SCHEMA_CONTRACT}.`
    });
  }

  if (
    input.storedChecksum &&
    input.incomingChecksum &&
    input.storedChecksum !== input.incomingChecksum
  ) {
    blocks.push({
      code: "checksum_incompatible",
      message: "Package checksum evidence is incompatible with the approved wave item."
    });
  }

  return blocks;
}

export function isApprovedProductionPackageWaveFresh(input: {
  approvedAt: string;
  now: string;
  maxAgeMs?: number;
}): boolean {
  return isProductionInboxApprovalFresh({
    approvedAt: input.approvedAt,
    now: input.now,
    maxAgeMs: input.maxAgeMs ?? PRODUCTION_INBOX_APPROVAL_MAX_AGE_MS
  });
}

export function collectOccupiedProductionPackageUnitKeys(input: {
  waveItems: ReadonlyArray<{ unitKey: string; status: string }>;
  queueItems?: ReadonlyArray<{ unitKey: string; status: BatchQueueItem["status"] }>;
}): Set<string> {
  const occupied = new Set<string>();
  for (const item of input.waveItems) {
    if (OCCUPIED_PACKAGE_ITEM_STATUSES.has(item.status)) {
      occupied.add(item.unitKey);
    }
  }
  if (input.queueItems) {
    for (const item of input.queueItems) {
      if (OCCUPIED_PACKAGE_ITEM_STATUSES.has(item.status)) {
        occupied.add(item.unitKey);
      }
    }
  }
  return occupied;
}

export function isProductionPackageWaveSelectableUnit(input: {
  item: BatchQueueItem;
  targetKey: string;
  stagingEvidence?: ProductionPackageStagingEvidence;
  occupied?: boolean;
}): { ok: true; writeCount: number } | { ok: false; code: BatchProductionPackageWaveBlockCode } {
  if (input.item.targetKey !== input.targetKey) {
    return { ok: false, code: "unit_target_mismatch" };
  }
  if (input.occupied) {
    return { ok: false, code: "already_delivered_or_pending_apply" };
  }
  const unitBlock = validateEligibleUnit(input.item, input.stagingEvidence);
  if (unitBlock) {
    return { ok: false, code: unitBlock.code };
  }
  const parsed = parseDryRunEvidence(input.item);
  return { ok: true, writeCount: parsed.writeCount };
}

function finalizeExplicitProductionUnitSelection(input: {
  input: EvaluateProductionPackageWaveEligibilityInput;
  hintedUnitKeys: string[];
  occupied: ReadonlySet<string>;
}): EvaluateProductionPackageWaveEligibilityResult {
  const unitIssues: ProductionPackageWaveUnitSelectionIssue[] = [];
  const selected: ProductionPackageWaveSelectedUnit[] = [];
  let totalPlannedRows = 0;

  for (const unitKey of input.hintedUnitKeys) {
    const item = input.input.snapshot.items.find((entry) => entry.unitKey === unitKey);
    if (!item) {
      unitIssues.push({
        unitKey,
        code: "unit_key_not_found",
        message: `Unit "${unitKey}" is not present in the active batch queue.`
      });
      continue;
    }
    if (item.targetKey !== input.input.targetKey) {
      unitIssues.push({
        unitKey,
        code: "unit_target_mismatch",
        message: `Unit "${unitKey}" target ${item.targetKey} does not match wave target ${input.input.targetKey}.`
      });
      continue;
    }
    if (input.occupied.has(unitKey)) {
      unitIssues.push({
        unitKey,
        code: "already_delivered_or_pending_apply",
        message: `Unit "${unitKey}" is already in an active or spent production package wave.`
      });
      continue;
    }

    const unitBlock = validateEligibleUnit(item, input.input.stagingEvidenceByUnitKey[unitKey]);
    if (unitBlock) {
      unitIssues.push({ unitKey, code: unitBlock.code, message: unitBlock.message });
      continue;
    }

    const parsed = parseDryRunEvidence(item);
    const stagingEvidence = input.input.stagingEvidenceByUnitKey[unitKey]!;
    const writeCount = parsed.writeCount;

    if (selected.length >= input.input.maxUnits) {
      unitIssues.push({
        unitKey,
        code: "unit_selection_exceeds_max_units",
        message: `Unit "${unitKey}" exceeds maxUnits (${input.input.maxUnits}).`
      });
      continue;
    }
    if (selected.length >= input.input.maxPackages) {
      unitIssues.push({
        unitKey,
        code: "package_bound_exceeded",
        message: `Unit "${unitKey}" exceeds maxPackages (${input.input.maxPackages}).`
      });
      continue;
    }
    if (totalPlannedRows + writeCount > input.input.maxRows) {
      unitIssues.push({
        unitKey,
        code: "row_bound_exceeded",
        message: `Unit "${unitKey}" would exceed maxRows (${input.input.maxRows}).`
      });
      continue;
    }

    selected.push({
      item,
      dryRunEvidence: parsed.evidence,
      stagingEvidence,
      writeCount,
      plannedPackageKey: buildProductionPackageWaveKey(
        input.input.snapshot.planId,
        "pending",
        item.unitKey
      )
    });
    totalPlannedRows += writeCount;
  }

  if (unitIssues.length > 0) {
    return {
      ok: false,
      blocks: [
        {
          code: "no_eligible_items",
          message: "One or more selected scopes failed production package revalidation."
        }
      ],
      unitIssues
    };
  }

  if (selected.length === 0) {
    return {
      ok: false,
      blocks: [
        {
          code: "no_eligible_items",
          message: "No valid staging-verified scopes were selected for production package approval."
        }
      ]
    };
  }

  selected.sort((a, b) => a.item.runOrder - b.item.runOrder);
  return { ok: true, selectedUnits: selected, totalPlannedRows };
}

function normalizeUnitKeyHints(unitKeys: readonly string[] | undefined): string[] {
  if (!unitKeys || unitKeys.length === 0) {
    return [];
  }
  const seen = new Set<string>();
  const normalized: string[] = [];
  for (const unitKey of unitKeys) {
    const trimmed = unitKey.trim();
    if (!trimmed || seen.has(trimmed)) {
      continue;
    }
    seen.add(trimmed);
    normalized.push(trimmed);
  }
  return normalized;
}

function validateEligibleUnit(
  item: BatchQueueItem,
  stagingEvidence: ProductionPackageStagingEvidence | undefined
): BatchProductionPackageWaveBlock | null {
  if (item.status !== "staging_canary_succeeded") {
    return {
      code: "not_staging_proven",
      message: `Unit "${item.unitKey}" is "${item.status}", not staging_canary_succeeded.`
    };
  }

  if (item.blockReasons.length > 0) {
    return {
      code: "active_blockers",
      message: `Unit "${item.unitKey}" has active blockers.`
    };
  }

  const dryRun = parseDryRunEvidence(item);
  if (dryRun.evidence.wroteToTarget !== false) {
    return {
      code: "dry_run_invariant_violated",
      message: `Unit "${item.unitKey}" dry-run report violates wroteToTarget=false.`
    };
  }

  const deleteCount = dryRun.evidence.deleteCount ?? 0;
  if (deleteCount > 0) {
    return {
      code: "delete_not_allowed",
      message: `Unit "${item.unitKey}" includes ${deleteCount} delete operation(s).`
    };
  }

  if (dryRun.writeCount <= 0) {
    return {
      code: "row_bound_exceeded",
      message: `Unit "${item.unitKey}" has no positive write count.`
    };
  }

  if (!stagingEvidence) {
    return {
      code: "staging_canary_required",
      message: `Unit "${item.unitKey}" has no staging-canary evidence.`
    };
  }

  if (!SUCCEEDED_STAGING_STATUSES.has(stagingEvidence.status)) {
    return {
      code: "staging_canary_not_succeeded",
      message: `Unit "${item.unitKey}" staging canary is "${stagingEvidence.status}", not succeeded.`
    };
  }

  return null;
}

function parseDryRunEvidence(item: BatchQueueItem): {
  evidence: ProductionPackageDryRunEvidence;
  writeCount: number;
} {
  const report = item.dryRunReport;
  const wroteToTarget = report?.wroteToTarget === false ? false : true;
  const evidence: ProductionPackageDryRunEvidence = {
    executionKey: report?.executionKey,
    wroteToTarget: wroteToTarget as false,
    insertCount: report?.insertCount ?? 0,
    updateCount: report?.updateCount ?? 0,
    deleteCount: readDeleteCount(report),
    rowsProcessed: report?.rowsProcessed,
    queueItemStatusAtApproval: item.status
  };
  if (wroteToTarget !== false) {
    return { evidence, writeCount: 0 };
  }
  const writeCount = evidence.insertCount + evidence.updateCount;
  return { evidence, writeCount };
}

function readDeleteCount(report: BatchDryRunReport | null | undefined): number {
  if (!report || typeof report !== "object") {
    return 0;
  }
  const extended = report as BatchDryRunReport & { deleteCount?: number };
  return Number.isFinite(extended.deleteCount) ? Number(extended.deleteCount) : 0;
}

function principalHasProjectScope(principal: AdminPrincipal, projectKey: string): boolean {
  return principal.scopes.includes("*") || principal.scopes.includes(projectKey);
}

function hasFreshStepUp(principal: AdminPrincipal, now: string): boolean {
  const satisfiedAt = principal.stepUpSatisfiedAt;
  if (!satisfiedAt) {
    return false;
  }
  const nowMs = Date.parse(now);
  const satisfiedMs = Date.parse(satisfiedAt);
  if (!Number.isFinite(nowMs) || !Number.isFinite(satisfiedMs)) {
    return false;
  }
  const ageMs = nowMs - satisfiedMs;
  return (
    ageMs >= -ADMIN_FRESH_STEP_UP_CLOCK_SKEW_MS &&
    ageMs <= PRODUCTION_INBOX_FRESH_STEP_UP_WINDOW_MS
  );
}
