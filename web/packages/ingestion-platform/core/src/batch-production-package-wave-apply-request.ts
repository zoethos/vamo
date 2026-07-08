/**
 * Request parsing for production package-wave consumer apply (IP-18.6.6).
 */

export interface ProductionPackageWaveApplyRequest {
  projectKey: string;
  packageId: string;
  auditReason: string;
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

function readString(value: unknown): string | undefined {
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : undefined;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
