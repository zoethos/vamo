import {
  type ConsumerContractExports,
  type ConsumerContractManifest,
  type SpecValidationResult
} from "./types.js";
import {
  ValidationBag,
  optionalString,
  optionalStringArray,
  parseYamlDocument,
  requireNumber,
  requireRecord,
  requireString
} from "./validation.js";

/**
 * Parse a consumer contract `manifest.yaml`. A consumer (e.g. Vamo) publishes
 * this bundle; the platform imports a pinned snapshot. The manifest is the entry
 * point the importer validates before copying any export file.
 */
export function parseConsumerContractManifest(
  input: string | unknown
): SpecValidationResult<ConsumerContractManifest> {
  const parsed = parseYamlDocument(input);
  if (!parsed.ok) {
    return parsed;
  }

  const errors = new ValidationBag();
  const root = requireRecord(parsed.value, "$", errors);

  if (!root) {
    return errors.finish(emptyManifest());
  }

  const kind = requireString(root, "kind", "kind", errors);
  if (kind !== undefined && kind !== "ingestion.consumer_contract") {
    errors.shape("kind", 'Expected "ingestion.consumer_contract".');
  }

  const exportsRecord = requireRecord(root.exports, "exports", errors);
  const contractExports = exportsRecord
    ? parseExports(exportsRecord, errors)
    : emptyExports();

  return errors.finish({
    normalizedSpecVersion: 1,
    kind: "ingestion.consumer_contract",
    consumer: requireString(root, "consumer", "consumer", errors) ?? "",
    profile: requireString(root, "profile", "profile", errors) ?? "",
    version: requireNumber(root, "version", "version", errors) ?? 0,
    title: optionalString(root, "title", "title", errors),
    description: optionalString(root, "description", "description", errors),
    exports: contractExports
  });
}

function parseExports(
  record: Record<string, unknown>,
  errors: ValidationBag
): ConsumerContractExports {
  const pipeline = requireString(record, "pipeline", "exports.pipeline", errors) ?? "";
  const target = requireString(record, "target", "exports.target", errors) ?? "";
  const fixtures = optionalStringArray(record, "fixtures", "exports.fixtures", errors);

  assertSafeBundlePath(pipeline, "exports.pipeline", errors);
  assertSafeBundlePath(target, "exports.target", errors);
  fixtures.forEach((fixture, index) => {
    assertSafeBundlePath(fixture, `exports.fixtures[${index}]`, errors);
  });

  return {
    pipeline,
    target,
    fixtures
  };
}

/**
 * Export paths are resolved relative to the bundle root at import time. Reject any
 * path that could escape the bundle (absolute, drive-rooted, or `..` traversal) so
 * a manifest cannot pull files from outside the published contract.
 */
function assertSafeBundlePath(value: string, path: string, errors: ValidationBag): void {
  if (value.length === 0) {
    return;
  }

  const normalized = value.replace(/\\/g, "/");
  const unsafe =
    normalized.startsWith("/") ||
    /^[a-zA-Z]:/.test(normalized) ||
    normalized.split("/").some((segment) => segment === "..");

  if (unsafe) {
    errors.shape(
      path,
      "Export paths must be relative to the bundle and cannot traverse upward."
    );
  }
}

function emptyManifest(): ConsumerContractManifest {
  return {
    normalizedSpecVersion: 1,
    kind: "ingestion.consumer_contract",
    consumer: "",
    profile: "",
    version: 0,
    exports: emptyExports()
  };
}

function emptyExports(): ConsumerContractExports {
  return {
    pipeline: "",
    target: "",
    fixtures: []
  };
}
