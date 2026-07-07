/**
 * Load persisted production package-wave state from the Confluendo control DB.
 */

import { Client, type QueryResult } from "pg";

import type {
  ProductionPackageDryRunEvidence,
  ProductionPackageStagingEvidence
} from "./batch-production-package-wave-policy.js";

export interface BatchProductionPackageWaveLoadPgClientLike {
  query<T extends Record<string, unknown> = Record<string, unknown>>(
    sql: string,
    values?: unknown[]
  ): Promise<QueryResult<T>>;
}

export interface LoadedProductionPackageWaveItem {
  id: string;
  unitKey: string;
  runOrder: number;
  status: string;
  plannedRowCount: number;
  packageKey: string | null;
  packageId: string | null;
  checksum: string | null;
  dryRunEvidence: ProductionPackageDryRunEvidence;
  stagingEvidence: ProductionPackageStagingEvidence;
  queueItemId: string;
  blockers: string[];
}

export interface LoadedProductionPackageWave {
  id: string;
  waveKey: string;
  batchPlanId: string;
  planKey: string;
  projectKey: string;
  targetKey: string;
  targetEnvironment: string;
  schemaContract: string;
  maxUnits: number;
  maxRows: number;
  maxPackages: number;
  status: string;
  auditReason: string;
  approvalAuditId: string | null;
  approvedAt: string;
  approvalExpiresAt: string;
  approvedBy: Record<string, unknown>;
  packageId: string | null;
  packageChecksum: string | null;
  deliveryAuditId: string | null;
  summary: Record<string, unknown>;
  items: LoadedProductionPackageWaveItem[];
}

export interface LoadProductionPackageWaveInput {
  connectionString?: string;
  client?: BatchProductionPackageWaveLoadPgClientLike;
  projectKey: string;
  waveKey?: string;
  approvalAuditId?: string;
}

interface WaveRow extends Record<string, unknown> {
  id: string;
  waveKey: string;
  batchPlanId: string;
  planKey: string;
  projectKey: string;
  targetKey: string;
  targetEnvironment: string;
  schemaContract: string;
  maxUnits: number;
  maxRows: number;
  maxPackages: number;
  status: string;
  auditReason: string;
  approvedAt: string | Date;
  approvalExpiresAt: string | Date;
  approvedBy: Record<string, unknown> | null;
  approvalAuditId: string | null;
  packageId: string | null;
  packageChecksum: string | null;
  deliveryAuditId: string | null;
  summary: Record<string, unknown> | null;
}

interface ItemRow extends Record<string, unknown> {
  id: string;
  unitKey: string;
  runOrder: number;
  status: string;
  plannedRowCount: number;
  packageKey: string | null;
  packageId: string | null;
  checksum: string | null;
  dryRunEvidence: ProductionPackageDryRunEvidence | null;
  stagingEvidence: ProductionPackageStagingEvidence | null;
  queueItemId: string;
  blockers: unknown;
}

export async function loadProductionPackageWave(
  input: LoadProductionPackageWaveInput
): Promise<LoadedProductionPackageWave | null> {
  if (!input.client && !input.connectionString) {
    throw new Error("Production package-wave load requires a server-side connection string or client.");
  }
  if (!input.waveKey?.trim() && !input.approvalAuditId?.trim()) {
    throw new Error("Either waveKey or approvalAuditId is required.");
  }

  const ownedClient = input.client ? undefined : new Client({ connectionString: input.connectionString });
  const client = input.client ?? ownedClient;
  if (!client) {
    throw new Error("Production package-wave load client could not be initialized.");
  }
  if (ownedClient) {
    await ownedClient.connect();
  }

  try {
    const values: unknown[] = [input.projectKey];
    let filter = "";
    if (input.waveKey?.trim()) {
      filter = "and w.wave_key = $2";
      values.push(input.waveKey.trim());
    } else {
      filter = "and w.approval_audit_id = $2";
      values.push(input.approvalAuditId!.trim());
    }

    const waveResult = await client.query<WaveRow>(
      `
        select
          w.id::text as id,
          w.wave_key as "waveKey",
          w.batch_plan_id::text as "batchPlanId",
          bp.plan_key as "planKey",
          p.project_key as "projectKey",
          w.target_key as "targetKey",
          w.target_environment as "targetEnvironment",
          w.schema_contract as "schemaContract",
          w.max_units as "maxUnits",
          w.max_rows as "maxRows",
          w.max_packages as "maxPackages",
          w.status,
          w.approval_reason as "auditReason",
          w.approved_at as "approvedAt",
          w.approval_expires_at as "approvalExpiresAt",
          w.approved_by as "approvedBy",
          w.approval_audit_id as "approvalAuditId",
          w.package_id as "packageId",
          w.package_checksum as "packageChecksum",
          w.delivery_audit_id as "deliveryAuditId",
          w.summary
        from ingestion_platform.ingestion_batch_production_package_waves w
        join ingestion_platform.ingestion_batch_plans bp on bp.id = w.batch_plan_id
        join ingestion_platform.ingestion_projects p on p.id = bp.project_id
        where p.project_key = $1
          ${filter}
        order by w.updated_at desc, w.id desc
        limit 1
      `,
      values
    );

    const wave = waveResult.rows[0];
    if (!wave) {
      return null;
    }

    const items = await client.query<ItemRow>(
      `
        select
          wi.id::text as id,
          wi.unit_key as "unitKey",
          wi.run_order as "runOrder",
          wi.status,
          wi.planned_row_count as "plannedRowCount",
          wi.package_key as "packageKey",
          wi.package_id as "packageId",
          wi.checksum,
          wi.dry_run_evidence as "dryRunEvidence",
          wi.staging_evidence as "stagingEvidence",
          wi.queue_item_id::text as "queueItemId",
          wi.blockers
        from ingestion_platform.ingestion_batch_production_package_wave_items wi
        where wi.wave_id = $1::bigint
        order by wi.run_order asc, wi.unit_key asc
      `,
      [wave.id]
    );

    return {
      id: wave.id,
      waveKey: wave.waveKey,
      batchPlanId: wave.batchPlanId,
      planKey: wave.planKey,
      projectKey: wave.projectKey,
      targetKey: wave.targetKey,
      targetEnvironment: wave.targetEnvironment,
      schemaContract: wave.schemaContract,
      maxUnits: wave.maxUnits,
      maxRows: wave.maxRows,
      maxPackages: wave.maxPackages,
      status: wave.status,
      auditReason: wave.auditReason,
      approvalAuditId: wave.approvalAuditId,
      approvedAt: toIsoString(wave.approvedAt) ?? "",
      approvalExpiresAt: toIsoString(wave.approvalExpiresAt) ?? "",
      approvedBy: wave.approvedBy ?? {},
      packageId: wave.packageId,
      packageChecksum: wave.packageChecksum,
      deliveryAuditId: wave.deliveryAuditId,
      summary: wave.summary ?? {},
      items: items.rows.map((row) => ({
        id: row.id,
        unitKey: row.unitKey,
        runOrder: row.runOrder,
        status: row.status,
        plannedRowCount: row.plannedRowCount,
        packageKey: row.packageKey,
        packageId: row.packageId,
        checksum: row.checksum,
        dryRunEvidence: (row.dryRunEvidence ?? {
          wroteToTarget: false,
          insertCount: 0,
          updateCount: 0
        }) as ProductionPackageDryRunEvidence,
        stagingEvidence: row.stagingEvidence ?? { status: "unknown" },
        queueItemId: row.queueItemId,
        blockers: Array.isArray(row.blockers) ? row.blockers.map(String) : []
      }))
    };
  } finally {
    if (ownedClient) {
      await ownedClient.end();
    }
  }
}

function toIsoString(value: string | Date | null | undefined): string | undefined {
  if (value instanceof Date) {
    return value.toISOString();
  }
  return typeof value === "string" ? value : undefined;
}
