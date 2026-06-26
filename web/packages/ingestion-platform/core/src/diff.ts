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
  return Object.fromEntries(columns.map((column) => [column, normalizeValue(record[column])]));
}

function stableStringify(value: unknown): string {
  if (Array.isArray(value)) {
    return `[${value.map((item) => stableStringify(item)).join(",")}]`;
  }

  if (value instanceof Date) {
    return JSON.stringify(value.toISOString());
  }

  if (value !== null && typeof value === "object") {
    const record = value as Record<string, unknown>;
    return `{${Object.keys(record)
      .sort()
      .map((key) => `${JSON.stringify(key)}:${stableStringify(normalizeValue(record[key]))}`)
      .join(",")}}`;
  }

  return JSON.stringify(normalizeValue(value));
}

function normalizeValue(value: unknown): unknown {
  if (value instanceof Date) {
    return value.toISOString();
  }

  return value;
}
