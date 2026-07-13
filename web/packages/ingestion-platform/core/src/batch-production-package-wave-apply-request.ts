/**
 * Request parsing for production package-wave consumer apply (IP-18.6.6).
 */

export interface ProductionPackageWaveApplyRequest {
  projectKey: string;
  packageId: string;
  auditReason: string;
}

export interface ProductionPackageWaveApplyWaveRequest {
  projectKey: string;
  waveKey: string;
  auditReason: string;
  packageIds?: string[];
  unitKeys?: string[];
  confirmation?: string;
}

export function parseProductionPackageWaveApplyRequest(
  value: unknown
): { ok: true; request: ProductionPackageWaveApplyRequest } | { ok: false; error: string } {
  if (!isRecord(value)) {
    return { ok: false, error: "Request body must be a JSON object." };
  }

  const packageId = readString(value.packageId);
  if (!packageId) {
    return { ok: false, error: "packageId is required." };
  }

  const auditReason = readString(value.auditReason);
  if (!auditReason) {
    return { ok: false, error: "A non-empty auditReason is required." };
  }

  return {
    ok: true,
    request: {
      projectKey: readString(value.projectKey) ?? "vamo",
      packageId,
      auditReason
    }
  };
}

export const PRODUCTION_PACKAGE_WAVE_APPLY_CONFIRMATION = "YES";

export function parseProductionPackageWaveApplyWaveRequest(
  value: unknown
): { ok: true; request: ProductionPackageWaveApplyWaveRequest } | { ok: false; error: string } {
  if (!isRecord(value)) {
    return { ok: false, error: "Request body must be a JSON object." };
  }

  const waveKey = readString(value.waveKey);
  if (!waveKey) {
    return { ok: false, error: "waveKey is required." };
  }

  const auditReason = readString(value.auditReason);
  if (!auditReason) {
    return { ok: false, error: "A non-empty auditReason is required." };
  }

  const confirmation = readString(value.confirmation);
  if (confirmation !== PRODUCTION_PACKAGE_WAVE_APPLY_CONFIRMATION) {
    return {
      ok: false,
      error: `confirmation must be ${PRODUCTION_PACKAGE_WAVE_APPLY_CONFIRMATION}.`
    };
  }

  const packageIds = readStringArray(value.packageIds);
  const unitKeys = readStringArray(value.unitKeys);

  return {
    ok: true,
    request: {
      projectKey: readString(value.projectKey) ?? "vamo",
      waveKey,
      auditReason,
      packageIds: packageIds.length > 0 ? packageIds : undefined,
      unitKeys: unitKeys.length > 0 ? unitKeys : undefined,
      confirmation
    }
  };
}

export function parseProductionPackageWaveApplyPreflightQuery(
  value: unknown
): { ok: true; packageId: string; projectKey: string } | { ok: false; error: string } {
  if (!isRecord(value)) {
    return { ok: false, error: "Query parameters must be an object." };
  }

  const packageId = readString(value.packageId);
  if (!packageId) {
    return { ok: false, error: "packageId is required." };
  }

  return {
    ok: true,
    packageId,
    projectKey: readString(value.projectKey) ?? "vamo"
  };
}

export function parseProductionPackageWaveApplyWavePreflightQuery(
  value: unknown
): {
  ok: true;
  query: {
    projectKey: string;
    waveKey: string;
    packageIds?: string[];
    unitKeys?: string[];
  };
} | { ok: false; error: string } {
  if (!isRecord(value)) {
    return { ok: false, error: "Query parameters must be an object." };
  }
  const waveKey = readString(value.waveKey);
  if (!waveKey) {
    return { ok: false, error: "waveKey is required." };
  }
  const packageIds = readStringArrayFromQuery(value.packageIds);
  const unitKeys = readStringArrayFromQuery(value.unitKeys);
  return {
    ok: true,
    query: {
      projectKey: readString(value.projectKey) ?? "vamo",
      waveKey,
      packageIds: packageIds.length > 0 ? packageIds : undefined,
      unitKeys: unitKeys.length > 0 ? unitKeys : undefined
    }
  };
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

function readStringArrayFromQuery(value: unknown): string[] {
  if (Array.isArray(value)) {
    return readStringArray(value);
  }
  if (typeof value === "string") {
    if (value.includes(",")) {
      return readStringArray(value.split(","));
    }
    const trimmed = value.trim();
    return trimmed ? [trimmed] : [];
  }
  return [];
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
