import {
  type ConsumerContractDisplaySpec,
  type ConsumerContractExports,
  type ConsumerContractManifest,
  type ConsumerDisplayFieldDetailSpec,
  type ConsumerDisplayFieldPresenter,
  type ConsumerDisplayFieldSpec,
  type SpecValidationResult
} from "./types.js";
import {
  ValidationBag,
  enumValue,
  optionalString,
  optionalStringArray,
  parseYamlDocument,
  requireArray,
  requireNumber,
  requireRecord,
  requireString
} from "./validation.js";

const DISPLAY_PRESENTERS = [
  "raw",
  "title_case",
  "vamo_poi_type",
  "vamo_feature_type_mapping"
] as const;

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
    exports: contractExports,
    display: parseDisplay(root.display, errors)
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

function parseDisplay(
  value: unknown,
  errors: ValidationBag
): ConsumerContractDisplaySpec | undefined {
  if (value === undefined) {
    return undefined;
  }

  const record = requireRecord(value, "display", errors);
  if (!record) {
    return undefined;
  }

  const queueRecord =
    record.queue === undefined ? undefined : requireRecord(record.queue, "display.queue", errors);

  return {
    queue: queueRecord
      ? {
          fields: parseDisplayFields(queueRecord, "display.queue.fields", errors)
        }
      : undefined
  };
}

function parseDisplayFields(
  record: Record<string, unknown>,
  path: string,
  errors: ValidationBag
): ConsumerDisplayFieldSpec[] {
  const fields = requireArray(record, "fields", path, errors) ?? [];
  return fields.flatMap((entry, index) => {
    const fieldPath = `${path}[${index}]`;
    const field = requireRecord(entry, fieldPath, errors);
    if (!field) {
      return [];
    }

    const key = requireString(field, "key", `${fieldPath}.key`, errors) ?? "";
    const label = requireString(field, "label", `${fieldPath}.label`, errors) ?? "";
    const source = requireString(field, "source", `${fieldPath}.source`, errors) ?? "";
    const presenter = parsePresenter(field.presenter, `${fieldPath}.presenter`, errors);
    const detail = parseDisplayDetail(field.detail, `${fieldPath}.detail`, errors);

    return [
      {
        key,
        label,
        source,
        presenter,
        detail
      }
    ];
  });
}

function parseDisplayDetail(
  value: unknown,
  path: string,
  errors: ValidationBag
): ConsumerDisplayFieldDetailSpec | undefined {
  if (value === undefined) {
    return undefined;
  }

  const record = requireRecord(value, path, errors);
  if (!record) {
    return undefined;
  }

  return {
    source: requireString(record, "source", `${path}.source`, errors) ?? "",
    presenter: parsePresenter(record.presenter, `${path}.presenter`, errors)
  };
}

function parsePresenter(
  value: unknown,
  path: string,
  errors: ValidationBag
): ConsumerDisplayFieldPresenter | undefined {
  if (value === undefined) {
    return undefined;
  }
  if (typeof value !== "string") {
    errors.shape(path, "Expected a display presenter string.");
    return undefined;
  }
  return enumValue(
    value.trim(),
    DISPLAY_PRESENTERS,
    path,
    "invalid_shape",
    errors
  ) as ConsumerDisplayFieldPresenter | undefined;
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
