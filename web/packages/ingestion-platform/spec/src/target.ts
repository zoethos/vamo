import {
  DATA_API_PRIVILEGES,
  TARGET_ADAPTERS,
  type DataApiPrivilege,
  type TargetEngineSpec,
  type TargetProjectSpec,
  type TargetSecuritySpec,
  type TargetShipmentSpec,
  type TargetTableSpec,
  type SpecValidationResult
} from "./types.js";
import {
  ValidationBag,
  enumValue,
  optionalBoolean,
  optionalString,
  optionalStringArray,
  parseYamlDocument,
  requireArray,
  requireNumber,
  requireRecord,
  requireString
} from "./validation.js";

export function parseTargetProjectSpec(
  input: string | unknown
): SpecValidationResult<TargetProjectSpec> {
  const parsed = parseYamlDocument(input);
  if (!parsed.ok) {
    return parsed;
  }

  const errors = new ValidationBag();
  const root = requireRecord(parsed.value, "$", errors);

  if (!root) {
    return errors.finish(emptyTargetProject());
  }

  const kind = requireString(root, "kind", "kind", errors);
  if (kind !== undefined && kind !== "ingestion.target") {
    errors.shape("kind", 'Expected "ingestion.target".');
  }

  const adapter =
    enumValue(
      requireString(root, "adapter", "adapter", errors),
      TARGET_ADAPTERS,
      "adapter",
      "unknown_adapter",
      errors
    ) ?? "postgres";
  const engineRecord = requireRecord(root.engine, "engine", errors);
  const securityRecord = requireRecord(root.security, "security", errors);
  const shipmentRecord = requireRecord(root.shipment, "shipment", errors);
  const engine = engineRecord ? parseEngine(engineRecord, errors) : emptyEngine();
  const security = securityRecord ? parseSecurity(securityRecord, errors) : emptySecurity();
  const shipment = shipmentRecord ? parseShipment(shipmentRecord, errors) : emptyShipment();

  validateTargetSecurity(engine, security, errors);

  return errors.finish({
    normalizedSpecVersion: 1,
    kind: "ingestion.target",
    version: requireNumber(root, "version", "version", errors) ?? 0,
    id: requireString(root, "id", "id", errors) ?? "",
    name: requireString(root, "name", "name", errors) ?? "",
    adapter,
    engine,
    security,
    shipment
  });
}

function parseEngine(record: Record<string, unknown>, errors: ValidationBag): TargetEngineSpec {
  const type =
    enumValue(
      requireString(record, "type", "engine.type", errors),
      TARGET_ADAPTERS,
      "engine.type",
      "unknown_adapter",
      errors
    ) ?? "postgres";

  return {
    type,
    dsnEnv: requireString(record, "dsnEnv", "engine.dsnEnv", errors) ?? "",
    serviceRoleSecretEnv: optionalString(
      record,
      "serviceRoleSecretEnv",
      "engine.serviceRoleSecretEnv",
      errors
    ),
    exposeServiceRoleToBrowser: optionalBoolean(
      record,
      "exposeServiceRoleToBrowser",
      "engine.exposeServiceRoleToBrowser",
      errors,
      false
    )
  };
}

function parseSecurity(record: Record<string, unknown>, errors: ValidationBag): TargetSecuritySpec {
  const writeMode = requireString(record, "writeMode", "security.writeMode", errors);
  if (writeMode !== undefined && writeMode !== "dry_run" && writeMode !== "approved_write") {
    errors.shape("security.writeMode", 'Expected "dry_run" or "approved_write".');
  }

  const requireExplicitDataApiGrants = optionalBoolean(
    record,
    "requireExplicitDataApiGrants",
    "security.requireExplicitDataApiGrants",
    errors,
    false
  );
  const dataApiRoles = optionalStringArray(
    record,
    "dataApiRoles",
    "security.dataApiRoles",
    errors
  );
  const dataApiPrivileges = optionalDataApiPrivileges(record, errors);

  return {
    serverSideOnly: optionalBoolean(record, "serverSideOnly", "security.serverSideOnly", errors, true),
    forbidBrowserServiceRole: optionalBoolean(
      record,
      "forbidBrowserServiceRole",
      "security.forbidBrowserServiceRole",
      errors,
      true
    ),
    requireRlsOnExposedSchemas: optionalBoolean(
      record,
      "requireRlsOnExposedSchemas",
      "security.requireRlsOnExposedSchemas",
      errors,
      true
    ),
    exposedSchemas: optionalStringArray(record, "exposedSchemas", "security.exposedSchemas", errors),
    requireExplicitDataApiGrants,
    dataApiRoles:
      dataApiRoles.length > 0
        ? dataApiRoles
        : requireExplicitDataApiGrants
          ? ["anon", "authenticated"]
          : [],
    dataApiPrivileges:
      dataApiPrivileges.length > 0
        ? dataApiPrivileges
        : requireExplicitDataApiGrants
          ? ["select"]
          : [],
    writeMode: writeMode === "approved_write" ? "approved_write" : "dry_run"
  };
}

function optionalDataApiPrivileges(
  record: Record<string, unknown>,
  errors: ValidationBag
): DataApiPrivilege[] {
  const value = record.dataApiPrivileges;
  if (value === undefined) {
    return [];
  }

  if (!Array.isArray(value)) {
    errors.shape("security.dataApiPrivileges", "Expected an array of Data API privileges.");
    return [];
  }

  return value.flatMap((item, index) => {
    if (typeof item !== "string" || item.trim().length === 0) {
      errors.shape(`security.dataApiPrivileges[${index}]`, "Expected a non-empty string.");
      return [];
    }

    const normalized = item.trim().toLowerCase();
    if ((DATA_API_PRIVILEGES as readonly string[]).includes(normalized)) {
      return [normalized as DataApiPrivilege];
    }

    errors.shape(
      `security.dataApiPrivileges[${index}]`,
      `Unknown Data API privilege "${item}". Allowed values: ${DATA_API_PRIVILEGES.join(", ")}.`
    );
    return [];
  });
}

function parseShipment(record: Record<string, unknown>, errors: ValidationBag): TargetShipmentSpec {
  const defaultMode = requireString(record, "defaultMode", "shipment.defaultMode", errors);
  if (defaultMode !== undefined && defaultMode !== "dry_run" && defaultMode !== "approved_write") {
    errors.shape("shipment.defaultMode", 'Expected "dry_run" or "approved_write".');
  }

  const tableValues = requireArray(record, "tables", "shipment.tables", errors);
  const tables = tableValues?.flatMap((value, index) => {
    const path = `shipment.tables[${index}]`;
    const tableRecord = requireRecord(value, path, errors);
    if (!tableRecord) {
      return [];
    }

    return [parseTable(tableRecord, path, errors)];
  });

  return {
    defaultMode: defaultMode === "approved_write" ? "approved_write" : "dry_run",
    tables: tables ?? []
  };
}

function parseTable(
  record: Record<string, unknown>,
  path: string,
  errors: ValidationBag
): TargetTableSpec {
  const mode = requireString(record, "mode", `${path}.mode`, errors);
  if (mode !== undefined && mode !== "insert" && mode !== "upsert" && mode !== "merge") {
    errors.shape(`${path}.mode`, 'Expected "insert", "upsert", or "merge".');
  }

  const upsertKeys = optionalStringArray(record, "upsertKeys", `${path}.upsertKeys`, errors);
  if (upsertKeys.length === 0) {
    errors.shape(
      `${path}.upsertKeys`,
      "At least one upsert key is required for deterministic dry-run identity."
    );
  }

  return {
    table: requireString(record, "table", `${path}.table`, errors) ?? "",
    mode: mode === "merge" ? "merge" : mode === "insert" ? "insert" : "upsert",
    upsertKeys
  };
}

function validateTargetSecurity(
  engine: TargetEngineSpec,
  security: TargetSecuritySpec,
  errors: ValidationBag
): void {
  if (engine.exposeServiceRoleToBrowser) {
    errors.add({
      code: "target_security_violation",
      path: "engine.exposeServiceRoleToBrowser",
      message: "Service-role credentials must never be exposed to browser/admin code."
    });
  }

  if (!security.serverSideOnly) {
    errors.add({
      code: "target_security_violation",
      path: "security.serverSideOnly",
      message: "Target credentials must stay behind a server-side boundary."
    });
  }

  if (!security.forbidBrowserServiceRole) {
    errors.add({
      code: "target_security_violation",
      path: "security.forbidBrowserServiceRole",
      message: "Target specs must explicitly forbid browser service-role exposure."
    });
  }
}

function emptyTargetProject(): TargetProjectSpec {
  return {
    normalizedSpecVersion: 1,
    kind: "ingestion.target",
    version: 0,
    id: "",
    name: "",
    adapter: "postgres",
    engine: emptyEngine(),
    security: emptySecurity(),
    shipment: emptyShipment()
  };
}

function emptyEngine(): TargetEngineSpec {
  return {
    type: "postgres",
    dsnEnv: "",
    exposeServiceRoleToBrowser: false
  };
}

function emptySecurity(): TargetSecuritySpec {
  return {
    serverSideOnly: true,
    forbidBrowserServiceRole: true,
    requireRlsOnExposedSchemas: true,
    exposedSchemas: [],
    requireExplicitDataApiGrants: false,
    dataApiRoles: [],
    dataApiPrivileges: [],
    writeMode: "dry_run"
  };
}

function emptyShipment(): TargetShipmentSpec {
  return {
    defaultMode: "dry_run",
    tables: []
  };
}
