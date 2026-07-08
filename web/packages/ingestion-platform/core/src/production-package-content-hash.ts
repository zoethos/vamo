/**
 * Deterministic production package content hashing (IP-18.6.5).
 *
 * Hashes only the deliverable candidate rows that materially define the inbox
 * package payload. Key order is canonicalized before digest.
 */

import { createHash } from "node:crypto";

import type { StagedCandidate } from "./pipeline-runner.js";
import { extractDeliverablePackageContentItems } from "./shipment-package.js";

export const PRODUCTION_PACKAGE_CONTENT_HASH_VERSION = 1 as const;

export interface ProductionPackageContentHashUnit {
  recordKey: string;
  items: Array<{
    itemKey: string;
    targetTable: string;
    operation: string;
    payload: Record<string, unknown>;
  }>;
}

export function buildProductionPackageContentUnits(
  candidates: readonly StagedCandidate[]
): ProductionPackageContentHashUnit[] {
  return [...candidates]
    .sort((left, right) => left.recordKey.localeCompare(right.recordKey))
    .map((candidate) => ({
      recordKey: candidate.recordKey,
      items: extractDeliverablePackageContentItems(candidate)
        .map((item) => ({
          itemKey: item.itemKey,
          targetTable: item.targetTable,
          operation: item.operation,
          payload: item.payload
        }))
        .sort((left, right) => left.itemKey.localeCompare(right.itemKey))
    }));
}

export function hashProductionPackageCandidateContent(
  candidates: readonly StagedCandidate[]
): string {
  const canonical = {
    version: PRODUCTION_PACKAGE_CONTENT_HASH_VERSION,
    units: buildProductionPackageContentUnits(candidates)
  };
  const serialized = canonicalizeJson(canonical);
  return createHash("sha256").update(serialized, "utf8").digest("hex");
}

export function canonicalizeJson(value: unknown): string {
  return JSON.stringify(sortJsonValue(value));
}

function sortJsonValue(value: unknown): unknown {
  if (Array.isArray(value)) {
    return value.map((entry) => sortJsonValue(entry));
  }
  if (isRecord(value)) {
    const sorted: Record<string, unknown> = {};
    for (const key of Object.keys(value).sort()) {
      sorted[key] = sortJsonValue(value[key]);
    }
    return sorted;
  }
  return value;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
