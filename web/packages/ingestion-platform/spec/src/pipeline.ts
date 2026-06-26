import {
  CURSOR_STRATEGIES,
  SOURCE_ADAPTERS,
  TARGET_ADAPTERS,
  type FieldMappingSpec,
  type PipelinePolicyRequests,
  type PipelineSpec,
  type PipelineSourceSpec,
  type PipelineTargetBindingSpec,
  type QualityGateSpec,
  type SourceLicenseSpec,
  type SpecValidationResult
} from "./types.js";
import {
  ValidationBag,
  enumValue,
  optionalBoolean,
  optionalNumber,
  optionalString,
  parseYamlDocument,
  requireArray,
  requireBoolean,
  requireNumber,
  requireRecord,
  requireString
} from "./validation.js";

export function parsePipelineSpec(input: string | unknown): SpecValidationResult<PipelineSpec> {
  const parsed = parseYamlDocument(input);
  if (!parsed.ok) {
    return parsed;
  }

  const errors = new ValidationBag();
  const root = requireRecord(parsed.value, "$", errors);

  if (!root) {
    return errors.finish(emptyPipeline());
  }

  const kind = requireString(root, "kind", "kind", errors);
  if (kind !== undefined && kind !== "ingestion.pipeline") {
    errors.shape("kind", 'Expected "ingestion.pipeline".');
  }

  const sourceRecord = requireRecord(root.source, "source", errors);
  const targetRecord = requireRecord(root.target, "target", errors);
  const cursorRecord = requireRecord(root.cursor, "cursor", errors);

  const source = sourceRecord ? parseSource(sourceRecord, errors) : emptySource();
  const target = targetRecord ? parseTargetBinding(targetRecord, errors) : emptyTargetBinding();
  const cursor = cursorRecord
    ? {
        strategy:
          enumValue(
            requireString(cursorRecord, "strategy", "cursor.strategy", errors),
            CURSOR_STRATEGIES,
            "cursor.strategy",
            "unknown_cursor_strategy",
            errors
          ) ?? "snapshot",
        field: optionalString(cursorRecord, "field", "cursor.field", errors)
      }
    : { strategy: "snapshot" as const };
  const policyRequests = parsePolicyRequests(root.policyRequests, errors);
  const mappings = parseMappings(root, errors);
  const qualityGates = parseQualityGates(root, errors);

  validatePolicyContradictions(source.license, policyRequests, errors);

  return errors.finish({
    normalizedSpecVersion: 1,
    kind: "ingestion.pipeline",
    version: requireNumber(root, "version", "version", errors) ?? 0,
    id: requireString(root, "id", "id", errors) ?? "",
    name: requireString(root, "name", "name", errors) ?? "",
    owner: requireString(root, "owner", "owner", errors) ?? "",
    source,
    target,
    cursor,
    policyRequests,
    mappings,
    qualityGates
  });
}

function parseSource(
  record: Record<string, unknown>,
  errors: ValidationBag
): PipelineSourceSpec {
  const adapter =
    enumValue(
      requireString(record, "adapter", "source.adapter", errors),
      SOURCE_ADAPTERS,
      "source.adapter",
      "unknown_adapter",
      errors
    ) ?? "fixture";
  const licenseRecord = requireRecord(record.license, "source.license", errors);

  return {
    id: requireString(record, "id", "source.id", errors) ?? "",
    name: requireString(record, "name", "source.name", errors) ?? "",
    adapter,
    license: licenseRecord ? parseLicense(licenseRecord, errors) : emptyLicense(),
    connection: readOptionalRecord(record.connection, "source.connection", errors)
  };
}

function parseLicense(
  record: Record<string, unknown>,
  errors: ValidationBag
): SourceLicenseSpec {
  return {
    name: requireString(record, "name", "source.license.name", errors) ?? "",
    attribution: requireString(record, "attribution", "source.license.attribution", errors) ?? "",
    url: optionalString(record, "url", "source.license.url", errors),
    canStoreFacts:
      requireBoolean(record, "canStoreFacts", "source.license.canStoreFacts", errors) ?? false,
    canStoreContent:
      requireBoolean(record, "canStoreContent", "source.license.canStoreContent", errors) ??
      false,
    canStoreMediaBytes:
      requireBoolean(
        record,
        "canStoreMediaBytes",
        "source.license.canStoreMediaBytes",
        errors
      ) ?? false,
    liveOnly: optionalBoolean(record, "liveOnly", "source.license.liveOnly", errors, false),
    retentionDays: optionalNumber(record, "retentionDays", "source.license.retentionDays", errors)
  };
}

function parseTargetBinding(
  record: Record<string, unknown>,
  errors: ValidationBag
): PipelineTargetBindingSpec {
  const adapter =
    enumValue(
      requireString(record, "adapter", "target.adapter", errors),
      TARGET_ADAPTERS,
      "target.adapter",
      "unknown_adapter",
      errors
    ) ?? "postgres";

  return {
    id: requireString(record, "id", "target.id", errors) ?? "",
    adapter,
    project: requireString(record, "project", "target.project", errors) ?? "",
    profile: requireString(record, "profile", "target.profile", errors) ?? "",
    dryRunOnly: optionalBoolean(record, "dryRunOnly", "target.dryRunOnly", errors, true)
  };
}

function parsePolicyRequests(
  value: unknown,
  errors: ValidationBag
): PipelinePolicyRequests {
  if (value === undefined) {
    return {
      storeFacts: true,
      storeContent: false,
      storeMediaBytes: false
    };
  }

  const record = requireRecord(value, "policyRequests", errors);
  if (!record) {
    return {
      storeFacts: true,
      storeContent: false,
      storeMediaBytes: false
    };
  }

  return {
    storeFacts: optionalBoolean(record, "storeFacts", "policyRequests.storeFacts", errors, true),
    storeContent: optionalBoolean(
      record,
      "storeContent",
      "policyRequests.storeContent",
      errors,
      false
    ),
    storeMediaBytes: optionalBoolean(
      record,
      "storeMediaBytes",
      "policyRequests.storeMediaBytes",
      errors,
      false
    )
  };
}

function parseMappings(root: Record<string, unknown>, errors: ValidationBag): FieldMappingSpec[] {
  const mappings = requireArray(root, "mappings", "mappings", errors);
  if (!mappings) {
    return [];
  }

  return mappings.flatMap((value, index) => {
    const path = `mappings[${index}]`;
    const record = requireRecord(value, path, errors);
    if (!record) {
      return [];
    }

    return [
      {
        from: requireString(record, "from", `${path}.from`, errors) ?? "",
        to: requireString(record, "to", `${path}.to`, errors) ?? "",
        transform: optionalString(record, "transform", `${path}.transform`, errors)
      }
    ];
  });
}

function parseQualityGates(
  root: Record<string, unknown>,
  errors: ValidationBag
): QualityGateSpec[] {
  const gates = root.qualityGates;
  if (gates === undefined) {
    return [];
  }

  const values = requireArray(root, "qualityGates", "qualityGates", errors);
  if (!values) {
    return [];
  }

  return values.flatMap((value, index) => {
    const path = `qualityGates[${index}]`;
    const record = requireRecord(value, path, errors);
    if (!record) {
      return [];
    }

    const severity = requireString(record, "severity", `${path}.severity`, errors);
    if (severity !== undefined && severity !== "warn" && severity !== "block") {
      errors.shape(`${path}.severity`, 'Expected "warn" or "block".');
    }

    return [
      {
        id: requireString(record, "id", `${path}.id`, errors) ?? "",
        type: requireString(record, "type", `${path}.type`, errors) ?? "",
        severity: severity === "block" ? "block" : "warn"
      }
    ];
  });
}

function validatePolicyContradictions(
  license: SourceLicenseSpec,
  requests: PipelinePolicyRequests,
  errors: ValidationBag
): void {
  if (requests.storeFacts && !license.canStoreFacts) {
    errors.add({
      code: "policy_contradiction",
      path: "policyRequests.storeFacts",
      message: "This source license does not allow durable fact storage."
    });
  }

  if (requests.storeContent && !license.canStoreContent) {
    errors.add({
      code: "policy_contradiction",
      path: "policyRequests.storeContent",
      message: "This source license does not allow durable content storage."
    });
  }

  if (requests.storeMediaBytes && !license.canStoreMediaBytes) {
    errors.add({
      code: "policy_contradiction",
      path: "policyRequests.storeMediaBytes",
      message: "This source license does not allow durable media-byte storage."
    });
  }

  if (license.liveOnly && (requests.storeContent || requests.storeMediaBytes)) {
    errors.add({
      code: "policy_contradiction",
      path: "source.license.liveOnly",
      message: "Live-only sources cannot request durable content or media-byte storage."
    });
  }
}

function readOptionalRecord(
  value: unknown,
  path: string,
  errors: ValidationBag
): Record<string, unknown> | undefined {
  if (value === undefined) {
    return undefined;
  }

  return requireRecord(value, path, errors);
}

function emptyPipeline(): PipelineSpec {
  return {
    normalizedSpecVersion: 1,
    kind: "ingestion.pipeline",
    version: 0,
    id: "",
    name: "",
    owner: "",
    source: emptySource(),
    target: emptyTargetBinding(),
    cursor: { strategy: "snapshot" },
    policyRequests: {
      storeFacts: false,
      storeContent: false,
      storeMediaBytes: false
    },
    mappings: [],
    qualityGates: []
  };
}

function emptySource(): PipelineSourceSpec {
  return {
    id: "",
    name: "",
    adapter: "fixture",
    license: emptyLicense()
  };
}

function emptyLicense(): SourceLicenseSpec {
  return {
    name: "",
    attribution: "",
    canStoreFacts: false,
    canStoreContent: false,
    canStoreMediaBytes: false,
    liveOnly: false
  };
}

function emptyTargetBinding(): PipelineTargetBindingSpec {
  return {
    id: "",
    adapter: "postgres",
    project: "",
    profile: "",
    dryRunOnly: true
  };
}
