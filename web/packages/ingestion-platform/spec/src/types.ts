export const SOURCE_ADAPTERS = [
  "fixture",
  "snapshot",
  "http_api",
  "sql",
  "manual_upload",
  "observation_stream"
] as const;

export const TARGET_ADAPTERS = ["postgres", "supabase_postgres"] as const;

export const DATA_API_PRIVILEGES = ["select", "insert", "update", "delete"] as const;

export const CURSOR_STRATEGIES = [
  "monotonic_row_id",
  "page_token",
  "offset",
  "snapshot"
] as const;

export type SourceAdapterName = (typeof SOURCE_ADAPTERS)[number];
export type TargetAdapterName = (typeof TARGET_ADAPTERS)[number];
export type CursorStrategy = (typeof CURSOR_STRATEGIES)[number];
export type DataApiPrivilege = (typeof DATA_API_PRIVILEGES)[number];

export interface SpecValidationError {
  code:
    | "invalid_yaml"
    | "invalid_shape"
    | "missing_required"
    | "unknown_adapter"
    | "unknown_cursor_strategy"
    | "policy_contradiction"
    | "target_security_violation";
  path: string;
  message: string;
}

export type SpecValidationResult<T> =
  | {
      ok: true;
      value: T;
      errors: [];
    }
  | {
      ok: false;
      errors: SpecValidationError[];
    };

export interface SourceLicenseSpec {
  name: string;
  attribution: string;
  url?: string;
  canStoreFacts: boolean;
  canStoreContent: boolean;
  canStoreMediaBytes: boolean;
  liveOnly: boolean;
  retentionDays?: number;
}

export interface PipelineSourceSpec {
  id: string;
  name: string;
  adapter: SourceAdapterName;
  license: SourceLicenseSpec;
  connection?: Record<string, unknown>;
}

export interface PipelineTargetBindingSpec {
  id: string;
  adapter: TargetAdapterName;
  project: string;
  profile: string;
  dryRunOnly: boolean;
}

export interface PipelineCursorSpec {
  strategy: CursorStrategy;
  field?: string;
}

export interface PipelinePolicyRequests {
  storeFacts: boolean;
  storeContent: boolean;
  storeMediaBytes: boolean;
}

export interface FieldMappingSpec {
  from: string;
  to: string;
  transform?: string;
}

export interface QualityGateSpec {
  id: string;
  type: string;
  severity: "warn" | "block";
}

export interface PipelineSpec {
  normalizedSpecVersion: 1;
  kind: "ingestion.pipeline";
  version: number;
  id: string;
  name: string;
  owner: string;
  source: PipelineSourceSpec;
  target: PipelineTargetBindingSpec;
  cursor: PipelineCursorSpec;
  policyRequests: PipelinePolicyRequests;
  mappings: FieldMappingSpec[];
  qualityGates: QualityGateSpec[];
}

export interface TargetEngineSpec {
  type: TargetAdapterName;
  dsnEnv: string;
  serviceRoleSecretEnv?: string;
  exposeServiceRoleToBrowser: boolean;
}

export interface TargetSecuritySpec {
  serverSideOnly: boolean;
  forbidBrowserServiceRole: boolean;
  requireRlsOnExposedSchemas: boolean;
  exposedSchemas: string[];
  requireExplicitDataApiGrants: boolean;
  dataApiRoles: string[];
  dataApiPrivileges: DataApiPrivilege[];
  writeMode: "dry_run" | "approved_write";
}

export interface TargetTableSpec {
  table: string;
  mode: "insert" | "upsert" | "merge";
  upsertKeys: string[];
}

export interface TargetShipmentSpec {
  defaultMode: "dry_run" | "approved_write";
  tables: TargetTableSpec[];
}

export interface TargetProjectSpec {
  normalizedSpecVersion: 1;
  kind: "ingestion.target";
  version: number;
  id: string;
  name: string;
  adapter: TargetAdapterName;
  engine: TargetEngineSpec;
  security: TargetSecuritySpec;
  shipment: TargetShipmentSpec;
}

export interface ConsumerContractExports {
  pipeline: string;
  target: string;
  fixtures: string[];
}

export interface ConsumerContractManifest {
  normalizedSpecVersion: 1;
  kind: "ingestion.consumer_contract";
  consumer: string;
  profile: string;
  version: number;
  title?: string;
  description?: string;
  exports: ConsumerContractExports;
}
