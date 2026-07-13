/**
 * Versioned snapshot intake — pure local-file validation and normalization (IP-18.8.9).
 *
 * Accepts a reviewed manifest plus locally supplied normalized JSONL. No HTTP,
 * provider APIs, target DB, control DB, staging, inbox, or consumer apply.
 */

import { createHash } from "node:crypto";
import { mkdirSync, mkdtempSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { resolve, sep } from "node:path";

import type { SnapshotReleaseManifest } from "./snapshot-release-manifest.js";

export const SNAPSHOT_INTAKE_CONFIRMATION_ENV = "CONFIRM_CONFLUENDO_SNAPSHOT_INTAKE" as const;
export const SNAPSHOT_INTAKE_CONFIRMATION_VALUE = "YES" as const;

export const SNAPSHOT_COVERAGE_REPORT_KIND = "ingestion.snapshot_coverage_report" as const;
export const SNAPSHOT_RELEASE_KIND = "ingestion.snapshot_release" as const;

export const DEFAULT_SNAPSHOT_ALLOWED_CATEGORIES = [
  "poi",
  "landmark",
  "restaurant",
  "transport"
] as const;

export const ALLOWED_SNAPSHOT_ROW_KEYS = new Set([
  "source_row_id",
  "source",
  "scope",
  "attribution",
  "media"
]);

export const ALLOWED_SNAPSHOT_SOURCE_KEYS = new Set(["id", "name", "latitude", "longitude"]);

export type SnapshotIntakeIssueCategory = "invalid" | "duplicate" | "out_of_scope";

export interface SnapshotIntakeRowIssue {
  lineNumber: number;
  category: SnapshotIntakeIssueCategory;
  reason: string;
}

export interface SnapshotCoverageReport {
  kind: typeof SNAPSHOT_COVERAGE_REPORT_KIND;
  releaseId: string;
  derivedFromValidRowsOnly: true;
  validRowCount: number;
  invalidRowCount: number;
  duplicateRowCount: number;
  outOfScopeRowCount: number;
  byCountry: Record<string, number>;
  byPoiType: Record<string, number>;
}

export interface SnapshotReleaseMetadata {
  kind: typeof SNAPSHOT_RELEASE_KIND;
  releaseId: string;
  sourceKey: string;
  sourceProvider: string;
  acquiredAt: string;
  provenanceUrl: string;
  sourceAttribution: string;
  licenseIdentifier: string;
  retentionStatement: string;
  intendedConsumer: string;
  intendedTarget: string;
  sourceFormat: SnapshotReleaseManifest["sourceFormat"];
  intakeCompletedAt: string;
  inputSha256: string;
  outputSha256: string;
  rowCounts: {
    valid: number;
    invalid: number;
    duplicate: number;
    outOfScope: number;
  };
}

export interface SnapshotIntakeArtifacts {
  sourceJsonl: string;
  releaseJson: string;
  coverageReportJson: string;
}

export type SnapshotIntakeResult =
  | {
      ok: true;
      accepted: true;
      inputSha256: string;
      issues: SnapshotIntakeRowIssue[];
      coverage: SnapshotCoverageReport;
      normalizedJsonl: string;
      release: SnapshotReleaseMetadata;
      artifacts: SnapshotIntakeArtifacts;
    }
  | {
      ok: true;
      accepted: false;
      inputSha256: string;
      issues: SnapshotIntakeRowIssue[];
      coverage: SnapshotCoverageReport;
      blocks: string[];
    }
  | {
      ok: false;
      blocks: string[];
    };

export function sha256Hex(content: string | Buffer): string {
  return createHash("sha256").update(content).digest("hex");
}

export function isOutputPathInsideRepo(input: { outputDir: string; repoRoot: string }): boolean {
  const resolvedOutput = resolve(input.outputDir);
  const resolvedRepo = resolve(input.repoRoot);
  return resolvedOutput === resolvedRepo || resolvedOutput.startsWith(`${resolvedRepo}${sep}`);
}

export function intakeVersionedSnapshot(input: {
  manifest: SnapshotReleaseManifest;
  inputContent: string;
  now?: string;
}): SnapshotIntakeResult {
  const blocks: string[] = [];
  if (!input.manifest.factStorageApproved) {
    blocks.push("fact_storage_not_approved");
  }

  const inputSha256 = sha256Hex(input.inputContent);
  if (inputSha256 !== input.manifest.expectedSha256.toLowerCase()) {
    blocks.push("checksum_mismatch");
  }

  if (blocks.length > 0) {
    return { ok: false, blocks };
  }

  const allowedCategories = new Set(
    (input.manifest.allowedCategories ?? [...DEFAULT_SNAPSHOT_ALLOWED_CATEGORIES]).map((entry) =>
      entry.toLowerCase()
    )
  );
  const parsedRows = parseJsonlLines(input.inputContent);
  const issues: SnapshotIntakeRowIssue[] = [];
  const seenSourceIds = new Set<string>();
  const validRows: NormalizedSnapshotRow[] = [];

  for (const entry of parsedRows) {
    const classification = classifyIntakeRow(entry.value, {
      manifest: input.manifest,
      allowedCategories
    });

    if (!classification.valid) {
      issues.push({
        lineNumber: entry.lineNumber,
        category: classification.category ?? "invalid",
        reason: classification.reason ?? "invalid_row"
      });
      continue;
    }

    const sourceId = classification.row!.source.id;
    if (seenSourceIds.has(sourceId)) {
      issues.push({
        lineNumber: entry.lineNumber,
        category: "duplicate",
        reason: "duplicate_source_id"
      });
      continue;
    }
    seenSourceIds.add(sourceId);
    validRows.push(classification.row!);
  }

  validRows.sort(compareNormalizedRows);
  const normalizedRows = validRows.map((row, index) => ({
    ...row,
    source_row_id: index + 1
  }));
  const normalizedJsonl = `${normalizedRows.map((row) => JSON.stringify(row)).join("\n")}\n`;
  const coverage = buildCoverageReport({
    manifest: input.manifest,
    issues,
    validRows: normalizedRows
  });

  const acceptanceBlocks = collectAcceptanceBlocks(issues);
  if (acceptanceBlocks.length > 0) {
    return {
      ok: true,
      accepted: false,
      inputSha256,
      issues,
      coverage,
      blocks: acceptanceBlocks
    };
  }

  const intakeCompletedAt = input.now ?? new Date().toISOString();
  const release: SnapshotReleaseMetadata = {
    kind: SNAPSHOT_RELEASE_KIND,
    releaseId: input.manifest.releaseId,
    sourceKey: input.manifest.sourceKey,
    sourceProvider: input.manifest.sourceProvider,
    acquiredAt: input.manifest.acquiredAt,
    provenanceUrl: input.manifest.provenanceUrl,
    sourceAttribution: input.manifest.sourceAttribution,
    licenseIdentifier: input.manifest.licenseIdentifier,
    retentionStatement: input.manifest.retentionStatement,
    intendedConsumer: input.manifest.intendedConsumer,
    intendedTarget: input.manifest.intendedTarget,
    sourceFormat: input.manifest.sourceFormat,
    intakeCompletedAt,
    inputSha256,
    outputSha256: sha256Hex(normalizedJsonl),
    rowCounts: {
      valid: coverage.validRowCount,
      invalid: coverage.invalidRowCount,
      duplicate: coverage.duplicateRowCount,
      outOfScope: coverage.outOfScopeRowCount
    }
  };

  return {
    ok: true,
    accepted: true,
    inputSha256,
    issues,
    coverage,
    normalizedJsonl,
    release,
    artifacts: buildSnapshotIntakeArtifacts({ release, coverage, normalizedJsonl })
  };
}

export function buildSnapshotIntakeArtifacts(input: {
  release: SnapshotReleaseMetadata;
  coverage: SnapshotCoverageReport;
  normalizedJsonl: string;
}): SnapshotIntakeArtifacts {
  return {
    sourceJsonl: input.normalizedJsonl,
    releaseJson: `${JSON.stringify(input.release, null, 2)}\n`,
    coverageReportJson: `${JSON.stringify(input.coverage, null, 2)}\n`
  };
}

export function writeSnapshotIntakeArtifacts(input: {
  outputDir: string;
  artifacts: SnapshotIntakeArtifacts;
}): void {
  mkdirSync(input.outputDir, { recursive: true });
  const stagingDir = mkdtempSync(resolve(tmpdir(), "confluendo-snapshot-intake-"));
  const fileNames = ["source.jsonl", "release.json", "coverage-report.json"] as const;
  const contents = [
    input.artifacts.sourceJsonl,
    input.artifacts.releaseJson,
    input.artifacts.coverageReportJson
  ];

  try {
    for (let index = 0; index < fileNames.length; index += 1) {
      writeFileSync(resolve(stagingDir, fileNames[index]!), contents[index]!, "utf8");
    }
    for (const fileName of fileNames) {
      renameSync(resolve(stagingDir, fileName), resolve(input.outputDir, fileName));
    }
  } finally {
    rmSync(stagingDir, { recursive: true, force: true });
  }
}

interface ParsedJsonlLine {
  lineNumber: number;
  value: unknown;
}

interface NormalizedSnapshotRow {
  source_row_id: number;
  source: {
    id: string;
    name: string;
    latitude: number;
    longitude: number;
  };
  scope: {
    geography: string;
    category: string;
  };
  attribution: string;
}

function parseJsonlLines(content: string): ParsedJsonlLine[] {
  const lines = content.split(/\r?\n/).filter((line) => line.trim().length > 0);
  return lines.map((line, index) => ({
    lineNumber: index + 1,
    value: JSON.parse(line) as unknown
  }));
}

function classifyIntakeRow(
  value: unknown,
  input: {
    manifest: SnapshotReleaseManifest;
    allowedCategories: Set<string>;
  }
): {
  valid: boolean;
  category?: SnapshotIntakeIssueCategory;
  reason?: string;
  row?: NormalizedSnapshotRow;
} {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return { valid: false, category: "invalid", reason: "invalid_record_shape" };
  }

  const record = value as Record<string, unknown>;
  for (const key of Object.keys(record)) {
    if (!ALLOWED_SNAPSHOT_ROW_KEYS.has(key)) {
      return { valid: false, category: "invalid", reason: "unknown_row_field" };
    }
  }

  const attribution = readTrimmedString(record.attribution);
  if (!attribution) {
    return { valid: false, category: "invalid", reason: "missing_attribution" };
  }
  if (attribution !== input.manifest.sourceAttribution) {
    return { valid: false, category: "invalid", reason: "attribution_mismatch" };
  }

  const scope = record.scope;
  if (!scope || typeof scope !== "object" || Array.isArray(scope)) {
    return { valid: false, category: "invalid", reason: "missing_scope_fields" };
  }
  const geography = readTrimmedString((scope as Record<string, unknown>).geography);
  const category = readTrimmedString((scope as Record<string, unknown>).category)?.toLowerCase();
  if (!geography || !category) {
    return { valid: false, category: "invalid", reason: "missing_scope_fields" };
  }
  if (!input.allowedCategories.has(category)) {
    return { valid: false, category: "out_of_scope", reason: "category_out_of_scope" };
  }

  const source = record.source;
  if (!source || typeof source !== "object" || Array.isArray(source)) {
    return { valid: false, category: "invalid", reason: "missing_source_object" };
  }
  const sourceRecord = source as Record<string, unknown>;
  for (const key of Object.keys(sourceRecord)) {
    if (!ALLOWED_SNAPSHOT_SOURCE_KEYS.has(key)) {
      return { valid: false, category: "invalid", reason: "unknown_source_field" };
    }
  }

  const sourceId = readTrimmedString(sourceRecord.id);
  const sourceName = readTrimmedString(sourceRecord.name);
  const latitude = readCoordinate(sourceRecord.latitude);
  const longitude = readCoordinate(sourceRecord.longitude);
  if (!sourceId || !sourceName || latitude === null || longitude === null) {
    return { valid: false, category: "invalid", reason: "missing_required_source_fields" };
  }

  if (record.media && typeof record.media === "object" && !Array.isArray(record.media)) {
    const media = record.media as Record<string, unknown>;
    if (media.bytesBase64) {
      return { valid: false, category: "invalid", reason: "media_bytes_forbidden" };
    }
    for (const key of Object.keys(media)) {
      if (key !== "bytesBase64") {
        return { valid: false, category: "invalid", reason: "unknown_media_field" };
      }
    }
  }

  return {
    valid: true,
    row: {
      source_row_id: 0,
      source: {
        id: sourceId,
        name: sourceName,
        latitude,
        longitude
      },
      scope: {
        geography,
        category
      },
      attribution
    }
  };
}

function buildCoverageReport(input: {
  manifest: SnapshotReleaseManifest;
  issues: SnapshotIntakeRowIssue[];
  validRows: NormalizedSnapshotRow[];
}): SnapshotCoverageReport {
  const byCountry: Record<string, number> = {};
  const byPoiType: Record<string, number> = {};

  for (const row of input.validRows) {
    const country = inferCountryFromGeography(row.scope.geography);
    byCountry[country] = (byCountry[country] ?? 0) + 1;
    byPoiType[row.scope.category] = (byPoiType[row.scope.category] ?? 0) + 1;
  }

  return {
    kind: SNAPSHOT_COVERAGE_REPORT_KIND,
    releaseId: input.manifest.releaseId,
    derivedFromValidRowsOnly: true,
    validRowCount: input.validRows.length,
    invalidRowCount: input.issues.filter((issue) => issue.category === "invalid").length,
    duplicateRowCount: input.issues.filter((issue) => issue.category === "duplicate").length,
    outOfScopeRowCount: input.issues.filter((issue) => issue.category === "out_of_scope").length,
    byCountry,
    byPoiType
  };
}

function collectAcceptanceBlocks(issues: SnapshotIntakeRowIssue[]): string[] {
  const blocks: string[] = [];
  if (issues.some((issue) => issue.category === "invalid")) {
    blocks.push("invalid_rows_present");
  }
  if (issues.some((issue) => issue.category === "duplicate")) {
    blocks.push("duplicate_rows_present");
  }
  if (issues.some((issue) => issue.category === "out_of_scope")) {
    blocks.push("out_of_scope_rows_present");
  }
  return blocks;
}

function compareNormalizedRows(left: NormalizedSnapshotRow, right: NormalizedSnapshotRow): number {
  const geographyCompare = left.scope.geography.localeCompare(right.scope.geography);
  if (geographyCompare !== 0) {
    return geographyCompare;
  }
  const categoryCompare = left.scope.category.localeCompare(right.scope.category);
  if (categoryCompare !== 0) {
    return categoryCompare;
  }
  return left.source.id.localeCompare(right.source.id);
}

function inferCountryFromGeography(geography: string): string {
  const parts = geography.split("-");
  return parts.length > 1 ? parts[parts.length - 1]! : geography;
}

function readTrimmedString(value: unknown): string | undefined {
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : undefined;
}

function readCoordinate(value: unknown): number | null {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    return null;
  }
  return value;
}
