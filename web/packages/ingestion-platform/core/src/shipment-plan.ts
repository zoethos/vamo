export type ShipmentOperation = "insert" | "update" | "delete" | "no_op";

export interface ShipmentPlanItem {
  targetTable: string;
  operation: ShipmentOperation;
  idempotencyKey: string;
  recordKey: string;
  checksum: string;
  previousChecksum?: string;
  payload: Record<string, unknown>;
}

export interface ShipmentPlanIncompatibility {
  code:
    | "missing_table"
    | "missing_column"
    | "missing_upsert_key"
    | "invalid_table_payload"
    | "target_query_failed";
  table: string;
  column?: string;
  recordKey?: string;
  message: string;
}

export interface ShipmentPlan {
  mode: "dry_run";
  targetId: string;
  targetProject: string;
  compatible: boolean;
  items: ShipmentPlanItem[];
  incompatibilities: ShipmentPlanIncompatibility[];
}

export interface ShipmentCandidateRow {
  recordKey: string;
  payload: Record<string, unknown>;
}
