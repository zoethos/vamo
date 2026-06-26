import { readFileSync } from "node:fs";
import { isAbsolute, relative, resolve } from "node:path";

export interface FixtureSourceRecord {
  lineNumber: number;
  record: Record<string, unknown>;
  recordKey: string;
  cursorValue: string | number;
}

export interface FixtureSourceIssue {
  lineNumber: number;
  reasonCode: "invalid_json" | "invalid_cursor" | "invalid_record_shape";
  reasonMessage: string;
  rawLine?: string;
}

export interface ReadFixtureBatchInput {
  fixturePath: string;
  rootDir?: string;
  cursorField?: string;
  startAfter?: string | number;
  limit: number;
}

export interface FixtureBatch {
  records: FixtureSourceRecord[];
  issues: FixtureSourceIssue[];
  lastCursorValue?: string | number;
}

export function readFixtureBatch(input: ReadFixtureBatchInput): FixtureBatch {
  if (input.limit <= 0) {
    return {
      records: [],
      issues: []
    };
  }

  const filePath = resolveFixturePath(input.fixturePath, input.rootDir);
  const lines = readFileSync(filePath, "utf8").split(/\r?\n/);
  const records: FixtureSourceRecord[] = [];
  const issues: FixtureSourceIssue[] = [];

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
        reasonMessage: error instanceof Error ? error.message : "Fixture row is not valid JSON.",
        rawLine
      });
      continue;
    }

    if (!isRecord(parsed)) {
      issues.push({
        lineNumber,
        reasonCode: "invalid_record_shape",
        reasonMessage: "Fixture row must be a JSON object.",
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
      record: parsed,
      recordKey: typeof sourceId === "string" && sourceId.trim().length > 0 ? sourceId.trim() : `line:${lineNumber}`,
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

export function compareCursorValues(left: string | number, right: string | number): number {
  if (typeof left === "number" && typeof right === "number") {
    return left - right;
  }

  return String(left).localeCompare(String(right));
}

function resolveFixturePath(fixturePath: string, rootDir = process.cwd()): string {
  const root = resolve(rootDir);
  const resolvedPath = isAbsolute(fixturePath) ? resolve(fixturePath) : resolve(root, fixturePath);
  const relativePath = relative(root, resolvedPath);

  if (relativePath.startsWith("..") || isAbsolute(relativePath)) {
    throw new Error(`Fixture path escapes root directory: ${fixturePath}`);
  }

  return resolvedPath;
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

function getPath(record: Record<string, unknown>, path: string): unknown {
  return path.split(".").reduce<unknown>((current, segment) => {
    if (!isRecord(current)) {
      return undefined;
    }

    return current[segment];
  }, record);
}
