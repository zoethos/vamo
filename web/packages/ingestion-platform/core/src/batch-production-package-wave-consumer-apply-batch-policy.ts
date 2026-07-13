/**
 * Pure batch consumer apply policy for production package waves (IP-18.8.4).
 */

import {
  ADMIN_FRESH_STEP_UP_CLOCK_SKEW_MS,
  type AdminPrincipal
} from "./admin-auth.js";
import { PRODUCTION_INBOX_FRESH_STEP_UP_WINDOW_MS } from "./production-inbox-policy.js";
import type { ProductionInboxApplyPreflight } from "../../adapters/target/src/postgres-production-inbox-apply.js";
import {
  evaluateProductionPackageConsumerApplyPreflight,
  type ProductionPackageConsumerApplyBlock
} from "./batch-production-package-wave-consumer-apply-policy.js";

export type ProductionPackageWaveBatchApplyBlockCode =
  | ProductionPackageConsumerApplyBlock["code"]
  | "wave_key_required"
  | "wave_not_found"
  | "wave_not_deliverable"
  | "no_apply_targets"
  | "package_not_in_wave"
  | "unit_not_in_wave";

export interface ProductionPackageWaveBatchApplyBlock {
  code: ProductionPackageWaveBatchApplyBlockCode;
  message: string;
}

export interface ProductionPackageWaveBatchApplyTarget {
  unitKey: string;
  packageId: string;
  preflight: ProductionInboxApplyPreflight;
}

export interface ProductionPackageWaveBatchApplyWaveItem {
  unitKey: string;
  packageId: string | null;
  status: string;
  consumerApplyStatus?: string | null;
}

export interface ProductionPackageWaveBatchApplyWaveContext {
  waveKey: string;
  status: string;
  items: ProductionPackageWaveBatchApplyWaveItem[];
}

export interface ResolveProductionPackageWaveBatchApplyTargetsInput {
  wave: ProductionPackageWaveBatchApplyWaveContext;
  packageIds?: readonly string[];
  unitKeys?: readonly string[];
  prefetchesByPackageId: Readonly<Record<string, ProductionInboxApplyPreflight>>;
}

export interface ResolveProductionPackageWaveBatchApplyTargetsResult {
  targets: ProductionPackageWaveBatchApplyTarget[];
  skippedAppliedPackageIds: string[];
  rejected: ProductionPackageWaveBatchApplyBlock[];
}

export interface EvaluateProductionPackageWaveBatchApplyInput {
  projectKey: string;
  waveKey: string;
  auditReason: string;
  principal: AdminPrincipal;
  wave: ProductionPackageWaveBatchApplyWaveContext;
  packageIds?: readonly string[];
  unitKeys?: readonly string[];
  prefetchesByPackageId: Readonly<Record<string, ProductionInboxApplyPreflight>>;
  applyDatabaseConfigured?: boolean;
  now?: string;
}

export type EvaluateProductionPackageWaveBatchApplyResult =
  | {
      ok: true;
      targets: ProductionPackageWaveBatchApplyTarget[];
      skippedAppliedPackageIds: string[];
    }
  | { ok: false; blocks: ProductionPackageWaveBatchApplyBlock[] };

const DELIVERABLE_WAVE_STATUSES = new Set(["delivered", "partial", "consumer_apply_pending"]);

export function resolveProductionPackageWaveBatchApplyTargets(
  input: ResolveProductionPackageWaveBatchApplyTargetsInput
): ResolveProductionPackageWaveBatchApplyTargetsResult {
  const rejected: ProductionPackageWaveBatchApplyBlock[] = [];
  const skippedAppliedPackageIds: string[] = [];
  const hintedPackageIds = normalizePackageIdHints(input.packageIds);
  const hintedUnitKeys = normalizeUnitKeyHints(input.unitKeys);
  const waveItemsByUnitKey = new Map(input.wave.items.map((item) => [item.unitKey, item]));
  const waveItemsByPackageId = new Map(
    input.wave.items
      .filter((item) => item.packageId)
      .map((item) => [item.packageId as string, item])
  );

  const selectedItems = (
    hintedPackageIds.length > 0
      ? hintedPackageIds.map((packageId) => {
          const item = waveItemsByPackageId.get(packageId);
          if (!item) {
            rejected.push({
              code: "package_not_in_wave",
              message: `Package "${packageId}" is not part of wave "${input.wave.waveKey}".`
            });
            return null;
          }
          return item;
        })
      : hintedUnitKeys.length > 0
        ? hintedUnitKeys.map((unitKey) => {
            const item = waveItemsByUnitKey.get(unitKey);
            if (!item) {
              rejected.push({
                code: "unit_not_in_wave",
                message: `Unit "${unitKey}" is not part of wave "${input.wave.waveKey}".`
              });
              return null;
            }
            return item;
          })
        : input.wave.items.filter(
            (item) =>
              item.packageId &&
              (item.status === "delivered" ||
                item.status === "production_package_delivered" ||
                item.consumerApplyStatus === "pending")
          )
  ).filter((item): item is ProductionPackageWaveBatchApplyWaveItem => item !== null);

  if (rejected.length > 0) {
    return { targets: [], skippedAppliedPackageIds, rejected };
  }

  const targets: ProductionPackageWaveBatchApplyTarget[] = [];
  for (const item of selectedItems) {
    if (!item?.packageId) {
      continue;
    }
    const preflight = input.prefetchesByPackageId[item.packageId];
    if (!preflight) {
      rejected.push({
        code: "package_not_found",
        message: `Package "${item.packageId}" was not found in production inbox preflight.`
      });
      continue;
    }
    const preflightBlocks = evaluateProductionPackageConsumerApplyPreflight(preflight);
    if (preflightBlocks.some((block) => block.code === "already_applied")) {
      skippedAppliedPackageIds.push(item.packageId);
      continue;
    }
    if (preflightBlocks.length > 0) {
      rejected.push(...preflightBlocks);
      continue;
    }
    targets.push({
      unitKey: item.unitKey,
      packageId: item.packageId,
      preflight
    });
  }

  return { targets, skippedAppliedPackageIds, rejected };
}

export function evaluateProductionPackageWaveBatchApply(
  input: EvaluateProductionPackageWaveBatchApplyInput
): EvaluateProductionPackageWaveBatchApplyResult {
  const blocks: ProductionPackageWaveBatchApplyBlock[] = [];
  const auditReason = input.auditReason.trim();
  const waveKey = input.waveKey.trim();
  const now = input.now ?? new Date().toISOString();

  if (input.applyDatabaseConfigured === false) {
    blocks.push({
      code: "apply_not_configured",
      message: "VAMO_PRODUCTION_INBOX_APPLY_DATABASE_URL is not configured for consumer apply."
    });
  }
  if (!waveKey) {
    blocks.push({
      code: "wave_key_required",
      message: "A non-empty waveKey is required to apply a production package wave."
    });
  }
  if (input.principal.role !== "admin") {
    blocks.push({
      code: "role_denied",
      message: "Consumer apply requires an ingestion_admin (role=admin) principal."
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
      message: "Consumer apply requires verified MFA step-up (AAL2)."
    });
  }
  if (!hasFreshStepUp(input.principal, now)) {
    blocks.push({
      code: "fresh_step_up_required",
      message: "Consumer apply requires a fresh MFA step-up."
    });
  }
  if (!auditReason) {
    blocks.push({
      code: "audit_reason_required",
      message: "A non-empty audit reason is required to apply delivered production inbox packages."
    });
  }
  if (!DELIVERABLE_WAVE_STATUSES.has(input.wave.status)) {
    blocks.push({
      code: "wave_not_deliverable",
      message: `Wave "${input.wave.waveKey}" must be delivered before consumer apply; got ${input.wave.status}.`
    });
  }

  if (blocks.length > 0) {
    return { ok: false, blocks };
  }

  const resolved = resolveProductionPackageWaveBatchApplyTargets({
    wave: input.wave,
    packageIds: input.packageIds,
    unitKeys: input.unitKeys,
    prefetchesByPackageId: input.prefetchesByPackageId
  });

  if (resolved.rejected.length > 0) {
    return { ok: false, blocks: resolved.rejected };
  }
  if (resolved.targets.length === 0) {
    return {
      ok: false,
      blocks: [
        {
          code: "no_apply_targets",
          message: "No delivered packages with pending apply items were selected for this wave."
        }
      ]
    };
  }

  return {
    ok: true,
    targets: resolved.targets,
    skippedAppliedPackageIds: resolved.skippedAppliedPackageIds
  };
}

export function summarizeProductionPackageWaveBatchApplyPreflight(
  targets: readonly ProductionPackageWaveBatchApplyTarget[],
  skippedAppliedPackageIds: readonly string[]
): {
  packageCount: number;
  totalInboxItems: number;
  pendingItemCount: number;
  appliedItemCount: number;
  targetTables: string[];
} {
  const targetTables = new Set<string>();
  let totalInboxItems = 0;
  let pendingItemCount = 0;
  let appliedItemCount = 0;
  for (const target of targets) {
    totalInboxItems += target.preflight.itemCount;
    pendingItemCount += target.preflight.pendingItemCount;
    appliedItemCount += target.preflight.items.filter((item) => item.applyStatus === "applied").length;
    for (const table of target.preflight.targetTables) {
      targetTables.add(table);
    }
  }
  return {
    packageCount: targets.length + skippedAppliedPackageIds.length,
    totalInboxItems,
    pendingItemCount,
    appliedItemCount,
    targetTables: [...targetTables].sort()
  };
}

function normalizePackageIdHints(packageIds: readonly string[] | undefined): string[] {
  if (!packageIds || packageIds.length === 0) {
    return [];
  }
  const seen = new Set<string>();
  const normalized: string[] = [];
  for (const packageId of packageIds) {
    const trimmed = packageId.trim();
    if (!trimmed || seen.has(trimmed)) {
      continue;
    }
    seen.add(trimmed);
    normalized.push(trimmed);
  }
  return normalized;
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
