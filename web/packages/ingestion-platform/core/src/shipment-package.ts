/**
 * Confluendo production-inbox package assembly.
 *
 * This module builds the logical package and row payloads that Confluendo will
 * deliver to a consumer inbox. It intentionally does NOT compute
 * `payload_checksum` or package checksum: those are computed by the target
 * Postgres adapter inside the destination database using jsonb::text, matching
 * Vamo's apply function.
 */

import type { StagedCandidate } from "./pipeline-runner.js";
import type { ProgressiveRunReport } from "./progressive-run.js";

export type ProductionInboxTargetTable = "location_canonicals" | "location_source_refs";
export type ProductionInboxOperation = "upsert";

export interface ProductionInboxPackageItem {
  itemKey: string;
  targetTable: ProductionInboxTargetTable;
  operation: ProductionInboxOperation;
  payload: Record<string, unknown>;
}

export interface ProductionInboxPackage {
  packageId: string;
  consumerKey: string;
  targetEnvironment: "production";
  schemaContract: "vamo-place-intelligence@1";
  status: "production_inbox_delivered";
  sourceManifest: Record<string, unknown>;
  attributionManifest: Record<string, unknown>;
  diffSummary: Record<string, unknown>;
  approvedBy: string;
  approvalReason: string;
  items: ProductionInboxPackageItem[];
}

export interface BuildProductionInboxPackageInput {
  packageId: string;
  consumerKey: "vamo" | (string & {});
  runReport: ProgressiveRunReport;
  candidates: StagedCandidate[];
  approvedBy: string;
  approvalReason: string;
  sourceManifest?: Record<string, unknown>;
  attributionManifest?: Record<string, unknown>;
}

const TARGET_TABLES: readonly ProductionInboxTargetTable[] = [
  "location_canonicals",
  "location_source_refs"
];

export function buildProductionInboxPackage(
  input: BuildProductionInboxPackageInput
): ProductionInboxPackage {
  if (input.packageId.trim().length === 0) {
    throw new Error("Production inbox package_id is required.");
  }
  if (input.approvedBy.trim().length === 0) {
    throw new Error("Production inbox approvedBy is required.");
  }
  if (input.approvalReason.trim().length === 0) {
    throw new Error("Production inbox approvalReason is required.");
  }

  const items = input.candidates.flatMap((candidate) =>
    extractDeliverablePackageContentItems(candidate)
  );
  if (items.length === 0) {
    throw new Error("Production inbox package has no deliverable items.");
  }

  return {
    packageId: input.packageId,
    consumerKey: input.consumerKey,
    targetEnvironment: "production",
    schemaContract: "vamo-place-intelligence@1",
    status: "production_inbox_delivered",
    sourceManifest: input.sourceManifest ?? {
      sourceId: input.runReport.sourceId,
      checkpoint: input.runReport.checkpoint,
      policyBlocks: input.runReport.policyBlocks,
      deadLetters: input.runReport.deadLetters
    },
    attributionManifest: input.attributionManifest ?? {
      sourceId: input.runReport.sourceId,
      attribution: "FSQ Open Source Places"
    },
    diffSummary: {
      ...input.runReport.shipmentDiff,
      wroteToTarget: input.runReport.wroteToTarget,
      reachedReview: input.runReport.reachedReview
    },
    approvedBy: input.approvedBy,
    approvalReason: input.approvalReason,
    items
  };
}

export function extractDeliverablePackageContentItems(
  candidate: StagedCandidate
): ProductionInboxPackageItem[] {
  return TARGET_TABLES.flatMap((targetTable) => {
    const payload = candidate.payload[targetTable];
    if (!isRecord(payload)) {
      return [];
    }
    const normalizedPayload = normalizePayloadForTarget(candidate, targetTable, payload);
    return [
      {
        itemKey: `${targetTable}:${itemIdentity(targetTable, normalizedPayload, candidate.recordKey)}`,
        targetTable,
        operation: "upsert",
        payload: normalizedPayload
      }
    ];
  });
}

function normalizePayloadForTarget(
  candidate: StagedCandidate,
  targetTable: ProductionInboxTargetTable,
  payload: Record<string, unknown>
): Record<string, unknown> {
  if (targetTable !== "location_source_refs") {
    return { ...payload };
  }

  const canonicalKey =
    readString(payload.canonical_key) ??
    readString(
      isRecord(candidate.payload.location_canonicals)
        ? candidate.payload.location_canonicals.canonical_key
        : undefined
    );

  if (!canonicalKey) {
    throw new Error(
      `Production inbox source ref for ${candidate.recordKey} is missing canonical_key.`
    );
  }

  return {
    ...payload,
    canonical_key: canonicalKey
  };
}

function itemIdentity(
  targetTable: ProductionInboxTargetTable,
  payload: Record<string, unknown>,
  fallback: string
): string {
  if (targetTable === "location_canonicals") {
    return readString(payload.canonical_key) ?? fallback;
  }
  return `${readString(payload.provider) ?? "unknown"}:${readString(payload.source_place_id) ?? fallback}`;
}

function readString(value: unknown): string | undefined {
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : undefined;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
