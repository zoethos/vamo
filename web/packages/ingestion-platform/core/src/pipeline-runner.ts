import { createHash } from "node:crypto";

import { readFixtureBatch, type FixtureSourceIssue } from "../../adapters/source/src/fixture-source.js";
import { evaluateRecordPolicy, hasPolicyDenial, type PolicyEvaluation } from "../../policy/src/index.js";
import type { FieldMappingSpec, PipelineSpec } from "../../spec/src/types.js";

export interface PipelineCheckpoint {
  cursorScope: string;
  cursorStrategy: PipelineSpec["cursor"]["strategy"];
  cursorValue: {
    last?: string | number;
  };
  lastRecordKey?: string;
  processedCount: number;
}

export interface StagedCandidate {
  recordKey: string;
  sourceLineNumber: number;
  sourceCursor: string | number;
  targetProject: string;
  targetProfile: string;
  payload: Record<string, unknown>;
}

export interface IngestionEvent {
  eventType: string;
  severity: "debug" | "info" | "warn" | "error";
  signal?: string;
  message: string;
  payload: Record<string, unknown>;
}

export interface DeadLetter {
  recordKey?: string;
  sourceLineNumber?: number;
  reasonCode: string;
  reasonMessage: string;
  payload: Record<string, unknown>;
}

export interface PipelineRunResult {
  candidates: StagedCandidate[];
  policyEvaluations: PolicyEvaluation[];
  events: IngestionEvent[];
  deadLetters: DeadLetter[];
  checkpoint: PipelineCheckpoint;
}

export interface RunFixturePipelineInput {
  pipeline: PipelineSpec;
  batchSize: number;
  checkpoint?: PipelineCheckpoint;
  fixtureRoot?: string;
}

interface MappingResult {
  payload: Record<string, unknown>;
  errors: Array<{
    reasonCode: string;
    reasonMessage: string;
    mapping: FieldMappingSpec;
  }>;
}

export async function runFixturePipeline(input: RunFixturePipelineInput): Promise<PipelineRunResult> {
  if (input.pipeline.source.adapter !== "fixture") {
    throw new Error(`Unsupported source adapter for fixture runner: ${input.pipeline.source.adapter}`);
  }

  const fixturePath = input.pipeline.source.connection?.fixturePath;
  if (typeof fixturePath !== "string" || fixturePath.trim().length === 0) {
    throw new Error("Fixture pipeline source must define source.connection.fixturePath.");
  }

  const startAfter = input.checkpoint?.cursorValue.last;
  const batch = readFixtureBatch({
    fixturePath,
    rootDir: input.fixtureRoot,
    cursorField: input.pipeline.cursor.field,
    startAfter,
    limit: input.batchSize
  });
  const candidates: StagedCandidate[] = [];
  const policyEvaluations: PolicyEvaluation[] = [];
  const deadLetters: DeadLetter[] = batch.issues.map(toDeadLetter);
  const events: IngestionEvent[] = [
    {
      eventType: "batch_started",
      severity: "info",
      message: "Fixture batch started.",
      payload: {
        pipelineId: input.pipeline.id,
        batchSize: input.batchSize,
        startAfter
      }
    }
  ];

  for (const issue of batch.issues) {
    events.push({
      eventType: "dead_letter",
      severity: "warn",
      signal: issue.reasonCode,
      message: issue.reasonMessage,
      payload: {
        lineNumber: issue.lineNumber
      }
    });
  }

  for (const row of batch.records) {
    const evaluations = evaluateRecordPolicy({
      pipeline: input.pipeline,
      record: row.record,
      recordKey: row.recordKey
    });
    policyEvaluations.push(...evaluations);

    if (hasPolicyDenial(evaluations)) {
      events.push({
        eventType: "policy_blocked",
        severity: "warn",
        signal: evaluations.find((evaluation) => evaluation.decision === "deny")?.reasonCode,
        message: "Fixture row was blocked by policy.",
        payload: {
          recordKey: row.recordKey,
          lineNumber: row.lineNumber
        }
      });
      continue;
    }

    const mapped = mapRecord(row.record, input.pipeline.mappings);
    if (mapped.errors.length > 0) {
      for (const error of mapped.errors) {
        deadLetters.push({
          recordKey: row.recordKey,
          sourceLineNumber: row.lineNumber,
          reasonCode: error.reasonCode,
          reasonMessage: error.reasonMessage,
          payload: {
            mapping: error.mapping,
            record: row.record
          }
        });
        events.push({
          eventType: "dead_letter",
          severity: "warn",
          signal: error.reasonCode,
          message: error.reasonMessage,
          payload: {
            recordKey: row.recordKey,
            lineNumber: row.lineNumber
          }
        });
      }
      continue;
    }

    candidates.push({
      recordKey: row.recordKey,
      sourceLineNumber: row.lineNumber,
      sourceCursor: row.cursorValue,
      targetProject: input.pipeline.target.project,
      targetProfile: input.pipeline.target.profile,
      payload: mapped.payload
    });
    events.push({
      eventType: "candidate_staged",
      severity: "info",
      message: "Fixture row staged as candidate.",
      payload: {
        recordKey: row.recordKey,
        lineNumber: row.lineNumber
      }
    });
  }

  const lastRecord = batch.records.at(-1);
  const checkpoint: PipelineCheckpoint = {
    cursorScope: input.pipeline.cursor.field ?? "fixture_line",
    cursorStrategy: input.pipeline.cursor.strategy,
    cursorValue: {
      last: batch.lastCursorValue ?? input.checkpoint?.cursorValue.last
    },
    lastRecordKey: lastRecord?.recordKey ?? input.checkpoint?.lastRecordKey,
    processedCount: (input.checkpoint?.processedCount ?? 0) + batch.records.length
  };

  events.push({
    eventType: "checkpoint_committed",
    severity: "info",
    message: "Fixture checkpoint committed.",
    payload: {
      cursorScope: checkpoint.cursorScope,
      cursorValue: checkpoint.cursorValue,
      processedCount: checkpoint.processedCount
    }
  });
  events.push({
    eventType: "batch_completed",
    severity: "info",
    message: "Fixture batch completed.",
    payload: {
      candidateCount: candidates.length,
      deadLetterCount: deadLetters.length,
      policyEvaluationCount: policyEvaluations.length
    }
  });

  return {
    candidates,
    policyEvaluations,
    events,
    deadLetters,
    checkpoint
  };
}

export function mapRecord(
  record: Record<string, unknown>,
  mappings: FieldMappingSpec[]
): MappingResult {
  const payload: Record<string, unknown> = {};
  const errors: MappingResult["errors"] = [];

  for (const mapping of mappings) {
    const rawValue =
      mapping.from !== undefined
        ? getPath(record, mapping.from)
        : mapping.value;
    if (rawValue === undefined || rawValue === null || rawValue === "") {
      errors.push({
        reasonCode: "missing_mapped_field",
        reasonMessage:
          mapping.from !== undefined
            ? `Required mapping source "${mapping.from}" is missing.`
            : `Required mapping literal for "${mapping.to}" is missing.`,
        mapping
      });
      continue;
    }

    const transformed = applyTransform(rawValue, mapping.transform);
    if (!transformed.ok) {
      errors.push({
        reasonCode: transformed.reasonCode,
        reasonMessage: transformed.reasonMessage,
        mapping
      });
      continue;
    }

    setPath(payload, mapping.to, transformed.value);
  }

  return {
    payload,
    errors
  };
}

function toDeadLetter(issue: FixtureSourceIssue): DeadLetter {
  return {
    sourceLineNumber: issue.lineNumber,
    reasonCode: issue.reasonCode,
    reasonMessage: issue.reasonMessage,
    payload: {
      rawLine: issue.rawLine
    }
  };
}

function applyTransform(
  value: unknown,
  transform?: string
):
  | {
      ok: true;
      value: unknown;
    }
  | {
      ok: false;
      reasonCode: string;
      reasonMessage: string;
    } {
  if (!transform) {
    return {
      ok: true,
      value
    };
  }

  if (transform === "trim") {
    return {
      ok: true,
      value: typeof value === "string" ? value.trim() : value
    };
  }

  if (transform === "lowercase") {
    return {
      ok: true,
      value: typeof value === "string" ? value.trim().toLowerCase() : value
    };
  }

  if (transform === "to_number") {
    const numberValue = typeof value === "number" ? value : Number(value);
    if (Number.isFinite(numberValue)) {
      return {
        ok: true,
        value: numberValue
      };
    }
  }

  if (transform === "stable_key") {
    return {
      ok: true,
      value: stableKey(value)
    };
  }

  if (transform === "deterministic_uuid") {
    return {
      ok: true,
      value: deterministicUuid(value)
    };
  }

  return {
    ok: false,
    reasonCode: "unsupported_transform",
    reasonMessage: `Unsupported or failed transform "${transform}".`
  };
}

function stableKey(value: unknown): string {
  return String(value)
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
}

function deterministicUuid(value: unknown): string {
  const bytes = createHash("sha256")
    .update(`ingestion-platform:${String(value)}`)
    .digest("hex")
    .slice(0, 32)
    .split("");
  bytes[12] = "5";
  bytes[16] = ((Number.parseInt(bytes[16] ?? "0", 16) & 0x3) | 0x8).toString(16);
  const hex = bytes.join("");

  return [
    hex.slice(0, 8),
    hex.slice(8, 12),
    hex.slice(12, 16),
    hex.slice(16, 20),
    hex.slice(20, 32)
  ].join("-");
}

function getPath(record: Record<string, unknown>, path: string): unknown {
  return path.split(".").reduce<unknown>((current, segment) => {
    if (typeof current !== "object" || current === null || Array.isArray(current)) {
      return undefined;
    }

    return (current as Record<string, unknown>)[segment];
  }, record);
}

function setPath(record: Record<string, unknown>, path: string, value: unknown): void {
  const parts = path.split(".");
  let current = record;

  for (const [index, part] of parts.entries()) {
    if (index === parts.length - 1) {
      current[part] = value;
      return;
    }

    const existing = current[part];
    if (typeof existing !== "object" || existing === null || Array.isArray(existing)) {
      current[part] = {};
    }

    current = current[part] as Record<string, unknown>;
  }
}
