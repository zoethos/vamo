import { createHash } from "node:crypto";

import type { ShipmentCandidateRow, ShipmentPlanItem } from "./shipment-plan.js";

export interface BuildShipmentDiffInput {
  targetTable: string;
  upsertKeys: string[];
  candidateRows: ShipmentCandidateRow[];
  existingRows: Array<Record<string, unknown>>;
}

export function buildShipmentDiff(input: BuildShipmentDiffInput): ShipmentPlanItem[] {
  const existingByKey = new Map(
    input.existingRows.map((row) => [recordIdentity(row, input.upsertKeys), row])
  );

  return input.candidateRows.map((candidate) => {
    const identity = recordIdentity(candidate.payload, input.upsertKeys);
    const existing = existingByKey.get(identity);
    const checksum = stableChecksum(candidate.payload);

    if (!existing) {
      return {
        targetTable: input.targetTable,
        operation: "insert",
        idempotencyKey: `${input.targetTable}:${identity}`,
        recordKey: candidate.recordKey,
        checksum,
        payload: candidate.payload
      };
    }

    const previousPayload = pickComparableColumns(existing, Object.keys(candidate.payload));
    const previousChecksum = stableChecksum(previousPayload);

    return {
      targetTable: input.targetTable,
      operation: checksum === previousChecksum ? "no_op" : "update",
      idempotencyKey: `${input.targetTable}:${identity}`,
      recordKey: candidate.recordKey,
      checksum,
      previousChecksum,
      payload: candidate.payload
    };
  });
}

export function recordIdentity(record: Record<string, unknown>, upsertKeys: string[]): string {
  return upsertKeys
    .map((key) => `${key}=${String(record[key])}`)
    .join("|");
}

export function stableChecksum(record: Record<string, unknown>): string {
  return createHash("sha256").update(stableStringify(record)).digest("hex");
}

function pickComparableColumns(
  record: Record<string, unknown>,
  columns: string[]
): Record<string, unknown> {
  return Object.fromEntries(
    columns.map((column) => [column, normalizeValue(record[column], column)])
  );
}

function stableStringify(value: unknown, key?: string): string {
  if (Array.isArray(value)) {
    return `[${value.map((item) => stableStringify(item, key)).join(",")}]`;
  }

  if (value instanceof Date) {
    return JSON.stringify(value.toISOString());
  }

  if (value !== null && typeof value === "object") {
    const record = value as Record<string, unknown>;
    return `{${Object.keys(record)
      .sort()
      .map((recordKey) => {
        const normalized = normalizeValue(record[recordKey], recordKey);
        return `${JSON.stringify(recordKey)}:${stableStringify(normalized, recordKey)}`;
      })
      .join(",")}}`;
  }

  return JSON.stringify(normalizeValue(value, key));
}

function normalizeValue(value: unknown, key?: string): unknown {
  if (value instanceof Date) {
    return value.toISOString();
  }

  if (typeof value === "string") {
    if (key && isTimestampKey(key) && isIsoLikeTimestamp(value)) {
      const parsed = new Date(value);
      if (!Number.isNaN(parsed.getTime())) {
        return parsed.toISOString();
      }
    }

    if (key && isNumericKey(key) && isNumericString(value)) {
      return Number(value);
    }
  }

  return value;
}

function isNumericKey(key: string): boolean {
  return /(^|_)(lat|lng|latitude|longitude|confidence|rank|score|weight)$/i.test(key);
}

function isTimestampKey(key: string): boolean {
  return /(^|_)(at|date|time)$/i.test(key);
}

function isIsoLikeTimestamp(value: string): boolean {
  return /^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}/.test(value);
}

function isNumericString(value: string): boolean {
  return /^-?(?:0|[1-9]\d*)(?:\.\d+)?$/.test(value.trim());
}
