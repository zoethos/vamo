/**
 * Pure production package-wave apply telemetry mapping (IP-18.6.4).
 *
 * Maps read-only confluendo_inbox apply evidence into control-plane and queue
 * statuses. No DB, network, provider, or consumer apply access.
 */

import type { ProductionInboxPackageApplyTelemetry } from "../../adapters/target/src/postgres-production-inbox-telemetry.js";
import {
  buildBatchQueueSnapshotFromItems,
  type BatchQueueItem,
  type BatchQueueItemStatus,
  type BatchQueueLatestProductionPackageWave,
  type BatchQueueLatestProductionPackageWaveItem,
  type BatchQueueSnapshot
} from "./batch-queue-read-model.js";

export type ProductionPackageConsumerApplyStatus = "pending" | "applied" | "failed" | "unknown";

export interface MappedProductionPackageApplyTelemetry {
  packageId: string;
  consumerApplyStatus: ProductionPackageConsumerApplyStatus;
  waveStatus: string;
  waveItemStatus: string;
  queueItemStatus: BatchQueueItemStatus;
  presentationStatus: string;
  evidence: Record<string, unknown>;
}

export function mapProductionInboxApplyTelemetry(
  telemetry: ProductionInboxPackageApplyTelemetry
): MappedProductionPackageApplyTelemetry {
  const consumerApplyStatus = deriveConsumerApplyStatus(telemetry);
  const waveStatus = mapWaveStatus(telemetry.shipmentStatus, consumerApplyStatus);
  const waveItemStatus = mapWaveItemStatus(consumerApplyStatus);
  const queueItemStatus = mapQueueItemStatus(consumerApplyStatus);
  const presentationStatus = mapPresentationStatus(consumerApplyStatus, telemetry.shipmentStatus);

  return {
    packageId: telemetry.packageId,
    consumerApplyStatus,
    waveStatus,
    waveItemStatus,
    queueItemStatus,
    presentationStatus,
    evidence: {
      source: "confluendo_inbox",
      shipmentStatus: telemetry.shipmentStatus,
      checksum: telemetry.checksum,
      appliedAt: telemetry.appliedAt,
      itemCount: telemetry.itemCount,
      pendingItemCount: telemetry.pendingItemCount,
      appliedItemCount: telemetry.appliedItemCount,
      skippedItemCount: telemetry.skippedItemCount,
      rejectedItemCount: telemetry.rejectedItemCount,
      latestApplyLogResult: telemetry.latestApplyLogResult,
      latestApplyLogDetail: telemetry.latestApplyLogDetail
    }
  };
}

export function mapProductionInboxApplyTelemetryByPackageId(
  packages: readonly ProductionInboxPackageApplyTelemetry[]
): Record<string, MappedProductionPackageApplyTelemetry> {
  return Object.fromEntries(
    packages.map((telemetry) => [telemetry.packageId, mapProductionInboxApplyTelemetry(telemetry)])
  );
}

export function collectDeliveredProductionPackageIds(
  wave: BatchQueueLatestProductionPackageWave | null | undefined
): string[] {
  if (!wave?.items?.length) {
    const fallback = wave?.packageId ?? wave?.packageKey;
    return fallback ? [fallback] : [];
  }
  const ids = wave.items
    .map((item) => item.packageId ?? item.packageKey)
    .filter((value): value is string => Boolean(value?.trim()));
  if (ids.length > 0) {
    return [...new Set(ids)];
  }
  const fallback = wave.packageId ?? wave.packageKey;
  return fallback ? [fallback] : [];
}

export function enrichBatchQueueSnapshotWithApplyTelemetry(input: {
  snapshot: BatchQueueSnapshot;
  telemetryByPackageId: Readonly<Record<string, MappedProductionPackageApplyTelemetry>>;
  telemetryAvailable: boolean;
}): BatchQueueSnapshot {
  const wave = input.snapshot.latestProductionPackageWave;
  if (!wave) {
    return input.snapshot;
  }

  const updatedWaveItems = (wave.items ?? []).map((item) =>
    applyTelemetryToWaveItem(item, resolvePackageId(item), input.telemetryByPackageId)
  );
  const mappedEntries = updatedWaveItems
    .map((item) => resolvePackageId(item))
    .map((packageId) => (packageId ? input.telemetryByPackageId[packageId] : undefined))
    .filter((entry): entry is MappedProductionPackageApplyTelemetry => Boolean(entry));

  const aggregate = aggregateWaveTelemetry(mappedEntries, wave, input.telemetryAvailable);
  const updatedWave: BatchQueueLatestProductionPackageWave = {
    ...wave,
    status: aggregate.waveStatus,
    consumerApplyStatus: aggregate.consumerApplyStatus,
    consumerApplyEvidence: aggregate.evidence,
    telemetrySource: aggregate.telemetrySource,
    items: updatedWaveItems
  };

  const packageIdByUnitKey = new Map(
    updatedWaveItems.map((item) => [item.unitKey, resolvePackageId(item)] as const)
  );
  const updatedItems = input.snapshot.items.map((item) => {
    const packageId = packageIdByUnitKey.get(item.unitKey);
    if (!packageId) {
      return item;
    }
    const mapped = input.telemetryByPackageId[packageId];
    if (!mapped) {
      return item;
    }
    return {
      ...item,
      status: mapped.queueItemStatus
    };
  });

  return buildBatchQueueSnapshotFromItems({
    planId: input.snapshot.planId,
    projectKey: input.snapshot.projectKey,
    targetKey: input.snapshot.targetKey,
    targetEnvironment: input.snapshot.targetEnvironment,
    sourceKey: input.snapshot.sourceKey,
    safetyMode: input.snapshot.safetyMode,
    items: updatedItems,
    planNextAction: input.snapshot.nextAction,
    latestExecution: input.snapshot.latestExecution,
    latestWave: input.snapshot.latestWave,
    latestProductionPackageWave: updatedWave
  });
}

function applyTelemetryToWaveItem(
  item: BatchQueueLatestProductionPackageWaveItem,
  packageId: string | null,
  telemetryByPackageId: Readonly<Record<string, MappedProductionPackageApplyTelemetry>>
): BatchQueueLatestProductionPackageWaveItem {
  if (!packageId) {
    return item;
  }
  const mapped = telemetryByPackageId[packageId];
  if (!mapped) {
    return {
      ...item,
      consumerApplyStatus: "unknown",
      telemetrySource: "missing"
    };
  }
  return {
    ...item,
    status: mapped.waveItemStatus,
    consumerApplyStatus: mapped.consumerApplyStatus,
    applyEvidence: mapped.evidence,
    telemetrySource: "inbox"
  };
}

function aggregateWaveTelemetry(
  mapped: MappedProductionPackageApplyTelemetry[],
  wave: BatchQueueLatestProductionPackageWave,
  telemetryAvailable: boolean
): {
  waveStatus: string;
  consumerApplyStatus: string;
  evidence: Record<string, unknown> | null;
  telemetrySource: "control" | "inbox" | "missing";
} {
  if (!telemetryAvailable) {
    return {
      waveStatus: wave.status,
      consumerApplyStatus: wave.consumerApplyStatus ?? "unknown",
      evidence: wave.consumerApplyEvidence ?? null,
      telemetrySource: "control"
    };
  }
  if (mapped.length === 0) {
    return {
      waveStatus: wave.status,
      consumerApplyStatus: "unknown",
      evidence: { source: "missing", reason: "package_not_found_in_inbox" },
      telemetrySource: "missing"
    };
  }

  const hasFailed = mapped.some((entry) => entry.consumerApplyStatus === "failed");
  const hasPending = mapped.some((entry) => entry.consumerApplyStatus === "pending");
  const allApplied = mapped.every((entry) => entry.consumerApplyStatus === "applied");

  let waveStatus = wave.status;
  let consumerApplyStatus: ProductionPackageConsumerApplyStatus = "unknown";
  if (hasFailed) {
    waveStatus = "consumer_apply_failed";
    consumerApplyStatus = "failed";
  } else if (allApplied) {
    waveStatus = "consumer_applied";
    consumerApplyStatus = "applied";
  } else if (hasPending) {
    waveStatus = "consumer_apply_pending";
    consumerApplyStatus = "pending";
  }

  return {
    waveStatus,
    consumerApplyStatus,
    evidence: {
      source: "confluendo_inbox",
      packages: mapped.map((entry) => ({
        packageId: entry.packageId,
        consumerApplyStatus: entry.consumerApplyStatus,
        presentationStatus: entry.presentationStatus,
        evidence: entry.evidence
      }))
    },
    telemetrySource: "inbox"
  };
}

function deriveConsumerApplyStatus(
  telemetry: ProductionInboxPackageApplyTelemetry
): ProductionPackageConsumerApplyStatus {
  if (telemetry.shipmentStatus === "consumer_applied") {
    return "applied";
  }
  if (telemetry.shipmentStatus === "consumer_apply_failed") {
    return "failed";
  }
  if (
    telemetry.shipmentStatus === "production_inbox_delivered" ||
    telemetry.shipmentStatus === "consumer_apply_pending"
  ) {
    return "pending";
  }
  if (telemetry.rejectedItemCount > 0) {
    return "failed";
  }
  if (telemetry.pendingItemCount > 0) {
    return "pending";
  }
  if (telemetry.itemCount > 0 && telemetry.appliedItemCount === telemetry.itemCount) {
    return "applied";
  }
  return "unknown";
}

function mapWaveStatus(
  shipmentStatus: string,
  consumerApplyStatus: ProductionPackageConsumerApplyStatus
): string {
  if (consumerApplyStatus === "applied") {
    return "consumer_applied";
  }
  if (consumerApplyStatus === "failed") {
    return "consumer_apply_failed";
  }
  if (consumerApplyStatus === "pending") {
    return "consumer_apply_pending";
  }
  if (shipmentStatus === "consumer_applied") {
    return "consumer_applied";
  }
  if (shipmentStatus === "consumer_apply_failed") {
    return "consumer_apply_failed";
  }
  return "delivered";
}

function mapWaveItemStatus(consumerApplyStatus: ProductionPackageConsumerApplyStatus): string {
  switch (consumerApplyStatus) {
    case "applied":
      return "consumer_applied";
    case "failed":
      return "consumer_apply_failed";
    case "pending":
      return "consumer_apply_pending";
    default:
      return "delivered";
  }
}

function mapQueueItemStatus(
  consumerApplyStatus: ProductionPackageConsumerApplyStatus
): BatchQueueItemStatus {
  switch (consumerApplyStatus) {
    case "applied":
      return "consumer_applied";
    case "failed":
      return "consumer_apply_failed";
    case "pending":
      return "consumer_apply_pending";
    default:
      return "production_package_delivered";
  }
}

function mapPresentationStatus(
  consumerApplyStatus: ProductionPackageConsumerApplyStatus,
  shipmentStatus: string
): string {
  switch (consumerApplyStatus) {
    case "applied":
      return "consumer_applied";
    case "failed":
      return "consumer_apply_failed";
    case "pending":
      return shipmentStatus === "production_inbox_delivered"
        ? "production_package_delivered"
        : "consumer_apply_pending";
    default:
      return shipmentStatus;
  }
}

function resolvePackageId(
  item: Pick<BatchQueueLatestProductionPackageWaveItem, "packageId" | "packageKey">
): string | null {
  const packageId = item.packageId ?? item.packageKey;
  return packageId?.trim() ? packageId : null;
}
