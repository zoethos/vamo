/**
 * Versioned snapshot release manifest — pure parse/validate (IP-18.8.9).
 *
 * Describes an approved local FSQ export intake. No network, DB, or provider calls.
 */

import { parse } from "yaml";

export const SNAPSHOT_RELEASE_MANIFEST_KIND = "ingestion.snapshot_release_manifest" as const;

export const SNAPSHOT_RELEASE_SOURCE_FORMATS = ["normalized_jsonl"] as const;

export type SnapshotReleaseSourceFormat = (typeof SNAPSHOT_RELEASE_SOURCE_FORMATS)[number];

export interface SnapshotReleaseManifest {
  kind: typeof SNAPSHOT_RELEASE_MANIFEST_KIND;
  sourceKey: string;
  sourceProvider: string;
  releaseId: string;
  acquiredAt: string;
  provenanceUrl: string;
  sourceAttribution: string;
  licenseIdentifier: string;
  factStorageApproved: boolean;
  retentionStatement: string;
  expectedSha256: string;
  sourceFormat: SnapshotReleaseSourceFormat;
  intendedConsumer: string;
  intendedTarget: string;
  allowedCategories?: string[];
}

export interface SnapshotReleaseManifestParseError {
  path: string;
  code: string;
  message: string;
}

export type ParseSnapshotReleaseManifestResult =
  | { ok: true; manifest: SnapshotReleaseManifest }
  | { ok: false; errors: SnapshotReleaseManifestParseError[] };

export function parseSnapshotReleaseManifest(
  input: string | unknown
): ParseSnapshotReleaseManifestResult {
  const value = typeof input === "string" ? parseYamlOrJson(input) : input;
  const errors: SnapshotReleaseManifestParseError[] = [];

  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return {
      ok: false,
      errors: [{ path: "$", code: "invalid_root", message: "Manifest must be an object." }]
    };
  }

  const record = value as Record<string, unknown>;
  if (record.kind !== SNAPSHOT_RELEASE_MANIFEST_KIND) {
    errors.push({
      path: "kind",
      code: "kind_mismatch",
      message: `kind must be ${SNAPSHOT_RELEASE_MANIFEST_KIND}.`
    });
  }

  const sourceKey = requireString(record, "sourceKey", errors);
  const sourceProvider = requireString(record, "sourceProvider", errors);
  const releaseId = requireString(record, "releaseId", errors);
  const acquiredAt = requireString(record, "acquiredAt", errors);
  const provenanceUrl = requireString(record, "provenanceUrl", errors);
  const sourceAttribution = requireString(record, "sourceAttribution", errors);
  const licenseIdentifier = requireString(record, "licenseIdentifier", errors);
  const retentionStatement = requireString(record, "retentionStatement", errors);
  const expectedSha256 = requireSha256(record, "expectedSha256", errors);
  const sourceFormat = requireSourceFormat(record, "sourceFormat", errors);
  const intendedConsumer = requireString(record, "intendedConsumer", errors);
  const intendedTarget = requireString(record, "intendedTarget", errors);
  const factStorageApproved = requireBoolean(record, "factStorageApproved", errors);
  const allowedCategories = parseAllowedCategories(record.allowedCategories, errors);

  if (errors.length > 0) {
    return { ok: false, errors };
  }

  return {
    ok: true,
    manifest: {
      kind: SNAPSHOT_RELEASE_MANIFEST_KIND,
      sourceKey: sourceKey!,
      sourceProvider: sourceProvider!,
      releaseId: releaseId!,
      acquiredAt: acquiredAt!,
      provenanceUrl: provenanceUrl!,
      sourceAttribution: sourceAttribution!,
      licenseIdentifier: licenseIdentifier!,
      factStorageApproved: factStorageApproved!,
      retentionStatement: retentionStatement!,
      expectedSha256: expectedSha256!,
      sourceFormat: sourceFormat!,
      intendedConsumer: intendedConsumer!,
      intendedTarget: intendedTarget!,
      allowedCategories
    }
  };
}

function parseYamlOrJson(input: string): unknown {
  const trimmed = input.trim();
  if (trimmed.startsWith("{")) {
    return JSON.parse(trimmed);
  }
  return parse(input);
}

function requireString(
  record: Record<string, unknown>,
  field: string,
  errors: SnapshotReleaseManifestParseError[]
): string | undefined {
  const value = record[field];
  if (typeof value !== "string" || value.trim().length === 0) {
    errors.push({
      path: field,
      code: "required_string",
      message: `${field} must be a non-empty string.`
    });
    return undefined;
  }
  return value.trim();
}

function requireBoolean(
  record: Record<string, unknown>,
  field: string,
  errors: SnapshotReleaseManifestParseError[]
): boolean | undefined {
  const value = record[field];
  if (typeof value !== "boolean") {
    errors.push({
      path: field,
      code: "required_boolean",
      message: `${field} must be a boolean.`
    });
    return undefined;
  }
  return value;
}

function requireSha256(
  record: Record<string, unknown>,
  field: string,
  errors: SnapshotReleaseManifestParseError[]
): string | undefined {
  const value = requireString(record, field, errors);
  if (!value) {
    return undefined;
  }
  if (!/^[a-f0-9]{64}$/i.test(value)) {
    errors.push({
      path: field,
      code: "invalid_sha256",
      message: `${field} must be a 64-character SHA-256 hex digest.`
    });
    return undefined;
  }
  return value.toLowerCase();
}

function requireSourceFormat(
  record: Record<string, unknown>,
  field: string,
  errors: SnapshotReleaseManifestParseError[]
): SnapshotReleaseSourceFormat | undefined {
  const value = requireString(record, field, errors);
  if (!value) {
    return undefined;
  }
  if (!SNAPSHOT_RELEASE_SOURCE_FORMATS.includes(value as SnapshotReleaseSourceFormat)) {
    errors.push({
      path: field,
      code: "invalid_source_format",
      message: `${field} must be one of: ${SNAPSHOT_RELEASE_SOURCE_FORMATS.join(", ")}.`
    });
    return undefined;
  }
  return value as SnapshotReleaseSourceFormat;
}

function parseAllowedCategories(
  value: unknown,
  errors: SnapshotReleaseManifestParseError[]
): string[] | undefined {
  if (value === undefined) {
    return undefined;
  }
  if (!Array.isArray(value) || value.some((entry) => typeof entry !== "string" || entry.trim().length === 0)) {
    errors.push({
      path: "allowedCategories",
      code: "invalid_allowed_categories",
      message: "allowedCategories must be an array of non-empty strings when provided."
    });
    return undefined;
  }
  return [...new Set(value.map((entry) => entry.trim().toLowerCase()))].sort();
}
