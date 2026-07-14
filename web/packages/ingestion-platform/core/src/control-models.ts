export const CONTROL_SCHEMA_NAME = "ingestion_platform" as const;

export const CONTROL_TABLES = [
  "ingestion_projects",
  "ingestion_admin_principals",
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
  "ingestion_audit_log",
  "ingestion_schedule_proposals",
  "ingestion_batch_plans",
  "ingestion_batch_queue_items",
  "ingestion_batch_dry_run_executions",
  "ingestion_batch_canary_waves",
  "ingestion_batch_canary_wave_items",
  "ingestion_autonomy_policies",
  "ingestion_autonomy_runs",
  "ingestion_batch_production_package_waves",
  "ingestion_batch_production_package_wave_items",
  "ingestion_snapshot_releases",
  "ingestion_snapshot_release_plan_bindings",
  "ingestion_snapshot_commission_requests",
  "ingestion_snapshot_activation_requests"
] as const;

export type AutonomyPolicyStatus = "active" | "paused" | "disabled" | "archived";

export type AutonomyRunPhase =
  | "planning"
  | "dry_run"
  | "staging_canary"
  | "production_inbox"
  | "corrective_action";

export type AutonomyRunStatus =
  | "started"
  | "advanced"
  | "paused"
  | "completed"
  | "failed"
  | "skipped";

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
