import { createHash } from "node:crypto";

import type { ShipmentCandidateRow, ShipmentPlanItem } from "./shipment-plan.js";

export interface BuildShipmentDiffInput {
  targetTable: string;
  upsertKeys: string[];
  candidateRows: ShipmentCandidateRow[];
  existingRows: Array<Record<string, unknown>>;
  columnTypes?: ColumnTypeHints;
}

export type ColumnTypeHints = Record<string, string | undefined>;

export function buildShipmentDiff(input: BuildShipmentDiffInput): ShipmentPlanItem[] {
  const existingByKey = new Map(
    input.existingRows.map((row) => [recordIdentity(row, input.upsertKeys), row])
  );

  return input.candidateRows.map((candidate) => {
    const identity = recordIdentity(candidate.payload, input.upsertKeys);
    const existing = existingByKey.get(identity);
    const checksum = stableChecksum(candidate.payload, input.columnTypes);

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

    const previousPayload = pickComparableColumns(
      existing,
      Object.keys(candidate.payload),
      input.columnTypes
    );
    const previousChecksum = stableChecksum(previousPayload, input.columnTypes);

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

export function stableChecksum(
  record: Record<string, unknown>,
  columnTypes?: ColumnTypeHints
): string {
  return createHash("sha256").update(stableStringify(record, undefined, columnTypes)).digest("hex");
}

function pickComparableColumns(
  record: Record<string, unknown>,
  columns: string[],
  columnTypes?: ColumnTypeHints
): Record<string, unknown> {
  return Object.fromEntries(
    columns.map((column) => [column, normalizeValue(record[column], column, columnTypes)])
  );
}

function stableStringify(
  value: unknown,
  key?: string,
  columnTypes?: ColumnTypeHints
): string {
  if (Array.isArray(value)) {
    return `[${value.map((item) => stableStringify(item, key, columnTypes)).join(",")}]`;
  }

  if (value instanceof Date) {
    return JSON.stringify(value.toISOString());
  }

  if (value !== null && typeof value === "object") {
    const record = value as Record<string, unknown>;
    return `{${Object.keys(record)
      .sort()
      .map((recordKey) => {
        const normalized = normalizeValue(record[recordKey], recordKey, columnTypes);
        return `${JSON.stringify(recordKey)}:${stableStringify(normalized, recordKey, columnTypes)}`;
      })
      .join(",")}}`;
  }

  return JSON.stringify(normalizeValue(value, key, columnTypes));
}

function normalizeValue(
  value: unknown,
  key?: string,
  columnTypes?: ColumnTypeHints
): unknown {
  if (value instanceof Date) {
    return value.toISOString();
  }

  if (typeof value === "string") {
    const columnType = key ? readColumnType(key, columnTypes) : undefined;
    if (
      key &&
      (isTemporalColumnType(columnType) || isTimestampKey(key)) &&
      isIsoLikeTimestamp(value)
    ) {
      const parsed = new Date(value);
      if (!Number.isNaN(parsed.getTime())) {
        return parsed.toISOString();
      }
    }

    if (
      key &&
      (isNumericColumnType(columnType) || isNumericKey(key)) &&
      isNumericString(value)
    ) {
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

function readColumnType(key: string, columnTypes?: ColumnTypeHints): string | undefined {
  return columnTypes?.[key]?.toLowerCase();
}

function isNumericColumnType(columnType?: string): boolean {
  if (!columnType) {
    return false;
  }

  return /^(smallint|integer|bigint|numeric|decimal|real|double precision|float|int2|int4|int8|float4|float8|serial|bigserial)(\b|$)/.test(
    columnType
  );
}

function isTemporalColumnType(columnType?: string): boolean {
  if (!columnType) {
    return false;
  }

  return /^(timestamp|date|time)(\b|$)/.test(columnType);
}

function isIsoLikeTimestamp(value: string): boolean {
  return /^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}/.test(value);
}

function isNumericString(value: string): boolean {
  return /^-?(?:0|[1-9]\d*)(?:\.\d+)?$/.test(value.trim());
}
