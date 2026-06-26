export const CONTROL_SCHEMA_NAME = "ingestion_platform" as const;

export const CONTROL_TABLES = [
  "ingestion_projects",
  "ingestion_specs",
  "ingestion_sources",
  "ingestion_targets",
  "ingestion_runs",
  "ingestion_tasks",
  "ingestion_worker_leases",
  "ingestion_checkpoints",
  "ingestion_events",
  "ingestion_dead_letters",
  "ingestion_artifacts",
  "ingestion_policy_evaluations",
  "ingestion_promotions",
  "ingestion_shipments",
  "ingestion_shipment_items",
  "ingestion_audit_log"
] as const;

export type ControlTableName = (typeof CONTROL_TABLES)[number];

export type IngestionRunStatus =
  | "queued"
  | "running"
  | "paused"
  | "succeeded"
  | "failed"
  | "cancelled";

export type IngestionTaskStatus =
  | "queued"
  | "running"
  | "paused"
  | "succeeded"
  | "failed"
  | "blocked"
  | "cancelled";

export type IngestionShipmentMode = "dry_run" | "approved_write";

export type IngestionShipmentStatus =
  | "planned"
  | "dry_run"
  | "approved"
  | "shipping"
  | "succeeded"
  | "failed"
  | "cancelled";

export interface ControlTableRef {
  schema: typeof CONTROL_SCHEMA_NAME;
  table: ControlTableName;
}

export interface CheckpointScopeKey {
  projectId: number;
  pipelineSpecId: number;
  sourceId: number;
  targetId: number;
  cursorScope: string;
}

export interface ShipmentItemIdentity {
  shipmentId: number;
  idempotencyKey: string;
}

export function controlTableRef(table: ControlTableName): ControlTableRef {
  return {
    schema: CONTROL_SCHEMA_NAME,
    table
  };
}

export function isControlTableName(value: string): value is ControlTableName {
  return (CONTROL_TABLES as readonly string[]).includes(value);
}
