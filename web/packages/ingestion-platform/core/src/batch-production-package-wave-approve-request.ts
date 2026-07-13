/**
 * Request parsing for production package-wave dashboard approval (IP-18.6.2).
 */

import { VAMO_PRODUCTION_PACKAGE_SCHEMA_CONTRACT } from "./batch-production-package-wave-policy.js";

export interface ProductionPackageWaveApproveRequest {
  projectKey: string;
  targetKey: string;
  targetEnvironment: "production";
  schemaContract: typeof VAMO_PRODUCTION_PACKAGE_SCHEMA_CONTRACT;
  maxUnits: number;
  maxRows: number;
  maxPackages: number;
  auditReason: string;
  unitKeys?: string[];
}

export function parseProductionPackageWaveApproveRequest(
  value: unknown
):
  | { ok: true; request: ProductionPackageWaveApproveRequest }
  | { ok: false; error: string } {
  if (!isRecord(value)) {
    return { ok: false, error: "Request body must be a JSON object." };
  }

  const targetKey = readString(value.targetKey);
  if (!targetKey) {
    return { ok: false, error: "targetKey is required." };
  }

  const targetEnvironment = readString(value.targetEnvironment);
  if (targetEnvironment !== "production") {
    return { ok: false, error: "targetEnvironment must be production for IP-18.6." };
  }

  const schemaContract = readString(value.schemaContract) ?? VAMO_PRODUCTION_PACKAGE_SCHEMA_CONTRACT;
  if (schemaContract !== VAMO_PRODUCTION_PACKAGE_SCHEMA_CONTRACT) {
    return {
      ok: false,
      error: `schemaContract must be ${VAMO_PRODUCTION_PACKAGE_SCHEMA_CONTRACT}.`
    };
  }

  const auditReason = readString(value.auditReason);
  if (!auditReason) {
    return { ok: false, error: "A non-empty auditReason is required." };
  }

  const maxUnits = readPositiveInt(value.maxUnits, 1);
  const maxRows = readPositiveInt(value.maxRows, 10);
  const maxPackages = readPositiveInt(value.maxPackages, 1);
  if (!maxUnits || !maxRows || !maxPackages) {
    return { ok: false, error: "maxUnits, maxRows, and maxPackages must be positive integers." };
  }

  const unitKeys = readStringArray(value.unitKeys);

  return {
    ok: true,
    request: {
      projectKey: readString(value.projectKey) ?? "vamo",
      targetKey,
      targetEnvironment: "production",
      schemaContract: VAMO_PRODUCTION_PACKAGE_SCHEMA_CONTRACT,
      maxUnits,
      maxRows,
      maxPackages,
      auditReason,
      unitKeys: unitKeys.length > 0 ? unitKeys : undefined
    }
  };
}

function readPositiveInt(value: unknown, fallback: number): number | undefined {
  if (value === undefined || value === null) {
    return fallback;
  }
  if (typeof value !== "number" || !Number.isInteger(value) || value < 1) {
    return undefined;
  }
  return value;
}

function readString(value: unknown): string | undefined {
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : undefined;
}

function readStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) {
    return [];
  }
  const seen = new Set<string>();
  const normalized: string[] = [];
  for (const entry of value) {
    if (typeof entry !== "string") {
      continue;
    }
    const trimmed = entry.trim();
    if (!trimmed || seen.has(trimmed)) {
      continue;
    }
    seen.add(trimmed);
    normalized.push(trimmed);
  }
  return normalized;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
