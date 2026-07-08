/**
 * Request parsing for batch staging-canary wave approval (IP-18.5 / unit selection).
 */

export interface BatchStagingCanaryWaveApproveRequest {
  projectKey: string;
  targetKey: string;
  targetEnvironment: "staging";
  maxUnits: number;
  maxRows: number;
  auditReason: string;
  unitKeys?: string[];
}

export function parseBatchStagingCanaryWaveApproveRequest(
  value: unknown
): { ok: true; request: BatchStagingCanaryWaveApproveRequest } | { ok: false; error: string } {
  if (!isRecord(value)) {
    return { ok: false, error: "Request body must be a JSON object." };
  }

  const targetKey = readString(value.targetKey);
  if (!targetKey) {
    return { ok: false, error: "targetKey is required." };
  }

  const targetEnvironment = readString(value.targetEnvironment) ?? "staging";
  if (targetEnvironment !== "staging") {
    return { ok: false, error: "targetEnvironment must be staging for IP-18.5." };
  }

  const auditReason = readString(value.auditReason);
  if (!auditReason) {
    return { ok: false, error: "A non-empty auditReason is required." };
  }

  const maxUnits = readPositiveInt(value.maxUnits, 1);
  const maxRows = readPositiveInt(value.maxRows, 50);
  if (!maxUnits || !maxRows) {
    return { ok: false, error: "maxUnits and maxRows must be positive integers." };
  }

  const unitKeys = readUnitKeys(value.unitKeys);

  return {
    ok: true,
    request: {
      projectKey: readString(value.projectKey) ?? "vamo",
      targetKey,
      targetEnvironment: "staging",
      maxUnits,
      maxRows,
      auditReason,
      ...(unitKeys.length > 0 ? { unitKeys } : {})
    }
  };
}

function readUnitKeys(value: unknown): string[] {
  if (!Array.isArray(value)) {
    return [];
  }
  const seen = new Set<string>();
  const keys: string[] = [];
  for (const entry of value) {
    if (typeof entry !== "string") {
      continue;
    }
    const trimmed = entry.trim();
    if (!trimmed || seen.has(trimmed)) {
      continue;
    }
    seen.add(trimmed);
    keys.push(trimmed);
  }
  return keys;
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

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
