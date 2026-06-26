import { readFileSync } from "node:fs";
import { basename, isAbsolute, relative, resolve } from "node:path";

import { compareCursorValues } from "./fixture-source.js";
import { findLocalSnapshotConnectionViolations } from "../../../spec/src/source-connection-policy.js";

export interface SnapshotSourceRecord {
  lineNumber: number;
  record: Record<string, unknown>;
  recordKey: string;
  cursorValue: string | number;
}

export interface SnapshotSourceIssue {
  lineNumber?: number;
  reasonCode:
    | "invalid_json"
    | "invalid_cursor"
    | "invalid_record_shape"
    | "missing_attribution";
  reasonMessage: string;
  rawLine?: string;
}

export interface SnapshotSourceMetadata {
  datasetId: string;
  datasetName: string;
  licenseName: string;
  attribution: string;
  datasetUrl?: string;
  downloadedAt?: string;
}

export interface ReadSnapshotBatchInput {
  snapshotPath: string;
  rootDir?: string;
  format?: string;
  connection?: Record<string, unknown>;
  cursorField?: string;
  startAfter?: string | number;
  limit: number;
  metadata: SnapshotSourceMetadata;
}

export interface SnapshotBatch {
  records: SnapshotSourceRecord[];
  issues: SnapshotSourceIssue[];
  lastCursorValue?: string | number;
}

export function readSnapshotBatch(input: ReadSnapshotBatchInput): SnapshotBatch {
  validateSnapshotInput(input);
  if (input.limit <= 0) {
    return {
      records: [],
      issues: []
    };
  }

  const filePath = resolveSnapshotPath(input.snapshotPath, input.rootDir);
  const lines = readFileSync(filePath, "utf8").split(/\r?\n/);
  const records: SnapshotSourceRecord[] = [];
  const issues: SnapshotSourceIssue[] = [];

  for (const [index, rawLine] of lines.entries()) {
    const lineNumber = index + 1;
    const line = rawLine.trim();
    if (line.length === 0) {
      continue;
    }

    let parsed: unknown;
    try {
      parsed = JSON.parse(line);
    } catch (error) {
      issues.push({
        lineNumber,
        reasonCode: "invalid_json",
        reasonMessage: error instanceof Error ? error.message : "Snapshot row is not valid JSON.",
        rawLine
      });
      continue;
    }

    if (!isRecord(parsed)) {
      issues.push({
        lineNumber,
        reasonCode: "invalid_record_shape",
        reasonMessage: "Snapshot row must be a JSON object.",
        rawLine
      });
      continue;
    }

    const attribution = readString(parsed, "attribution") ?? input.metadata.attribution;
    if (!attribution) {
      issues.push({
        lineNumber,
        reasonCode: "missing_attribution",
        reasonMessage: "Snapshot row needs attribution from the row or source metadata.",
        rawLine
      });
      continue;
    }

    const cursorValue = input.cursorField ? getPath(parsed, input.cursorField) : lineNumber;
    if (!isCursorValue(cursorValue)) {
      issues.push({
        lineNumber,
        reasonCode: "invalid_cursor",
        reasonMessage: `Cursor field "${input.cursorField ?? "lineNumber"}" must be a string or number.`,
        rawLine
      });
      continue;
    }

    if (
      input.startAfter !== undefined &&
      compareCursorValues(cursorValue, input.startAfter) <= 0
    ) {
      continue;
    }

    const sourceId = getPath(parsed, "source.id");
    records.push({
      lineNumber,
      record: withSnapshotMetadata(parsed, input.metadata, attribution, filePath),
      recordKey:
        typeof sourceId === "string" && sourceId.trim().length > 0
          ? sourceId.trim()
          : `line:${lineNumber}`,
      cursorValue
    });

    if (records.length >= input.limit) {
      break;
    }
  }

  return {
    records,
    issues,
    lastCursorValue: records.at(-1)?.cursorValue
  };
}

function validateSnapshotInput(input: ReadSnapshotBatchInput): void {
  if (input.format && input.format !== "jsonl") {
    throw new Error(`Unsupported snapshot format: ${input.format}`);
  }

  const violations = findLocalSnapshotConnectionViolations(
    {
      ...input.connection,
      snapshotPath: input.snapshotPath
    },
    { pathPrefix: "source.connection", requireSnapshotPath: true }
  );
  if (violations.length > 0) {
    throw new Error(violations[0].message);
  }
}

function resolveSnapshotPath(snapshotPath: string, rootDir = process.cwd()): string {
  const root = resolve(rootDir);
  const resolvedPath = isAbsolute(snapshotPath) ? resolve(snapshotPath) : resolve(root, snapshotPath);
  const relativePath = relative(root, resolvedPath);

  if (relativePath.startsWith("..") || isAbsolute(relativePath)) {
    throw new Error(`Snapshot path escapes root directory: ${snapshotPath}`);
  }

  return resolvedPath;
}

function withSnapshotMetadata(
  record: Record<string, unknown>,
  metadata: SnapshotSourceMetadata,
  attribution: string,
  filePath: string
): Record<string, unknown> {
  return {
    ...record,
    attribution,
    _ingestion: {
      sourceAdapter: "snapshot",
      datasetId: metadata.datasetId,
      datasetName: metadata.datasetName,
      licenseName: metadata.licenseName,
      attribution,
      datasetUrl: metadata.datasetUrl,
      downloadedAt: metadata.downloadedAt,
      snapshotFile: basename(filePath)
    }
  };
}

function isCursorValue(value: unknown): value is string | number {
  return (
    (typeof value === "string" && value.trim().length > 0) ||
    (typeof value === "number" && Number.isFinite(value))
  );
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function readString(record: Record<string, unknown>, path: string): string | undefined {
  const value = getPath(record, path);
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : undefined;
}

function getPath(record: Record<string, unknown>, path: string): unknown {
  return path.split(".").reduce<unknown>((current, segment) => {
    if (!isRecord(current)) {
      return undefined;
    }

    return current[segment];
  }, record);
}
