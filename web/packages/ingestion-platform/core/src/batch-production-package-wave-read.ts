/**
 * Production package-wave control-plane read helpers (IP-18.6.2).
 *
 * Loads staging-canary evidence and occupied production package units from the
 * Confluendo control DB only. No consumer inbox or product-table access.
 */

import { Client, type QueryResult } from "pg";

import type { ProductionPackageStagingEvidence } from "./batch-production-package-wave-policy.js";
import { collectOccupiedProductionPackageUnitKeys } from "./batch-production-package-wave-policy.js";
import type { BatchQueueItemStatus } from "./batch-queue-read-model.js";

export interface ProductionPackageWaveReadPgClientLike {
  query<T extends Record<string, unknown> = Record<string, unknown>>(
    sql: string,
    values?: unknown[]
  ): Promise<QueryResult<T>>;
}

export interface ProductionPackageWaveApprovalContext {
  stagingEvidenceByUnitKey: Record<string, ProductionPackageStagingEvidence>;
  occupiedUnitKeys: Set<string>;
  hasPriorDeliveredPackage: boolean;
}

export interface LoadProductionPackageWaveApprovalContextInput {
  connectionString?: string;
  client?: ProductionPackageWaveReadPgClientLike;
  projectKey: string;
  targetKey: string;
}

interface StagingEvidenceRow extends Record<string, unknown> {
  unitKey: string;
  itemStatus: string;
  shipmentId: string | null;
  shipmentKey: string | null;
  shipmentStatus: string | null;
}

interface OccupiedRow extends Record<string, unknown> {
  unitKey: string;
  status: string;
}

const UNDEFINED_TABLE = "42P01";

export async function loadProductionPackageWaveApprovalContext(
  input: LoadProductionPackageWaveApprovalContextInput
): Promise<ProductionPackageWaveApprovalContext> {
  const { client, ownedClient } = await openClient(input.client, input.connectionString);

  try {
    const stagingEvidenceByUnitKey: Record<string, ProductionPackageStagingEvidence> = {};
    const waveItems: Array<{ unitKey: string; status: string }> = [];
    const queueItems: Array<{ unitKey: string; status: BatchQueueItemStatus }> = [];
    let hasPriorDeliveredPackage = false;

    try {
      const stagingRows = await client.query<StagingEvidenceRow>(
        `
          select distinct on (wi.unit_key)
            wi.unit_key as "unitKey",
            wi.status as "itemStatus",
            wi.shipment_id::text as "shipmentId",
            s.shipment_key as "shipmentKey",
            s.status as "shipmentStatus"
          from ingestion_platform.ingestion_batch_canary_wave_items wi
          join ingestion_platform.ingestion_batch_canary_waves w on w.id = wi.wave_id
          join ingestion_platform.ingestion_batch_plans bp on bp.id = w.batch_plan_id
          join ingestion_platform.ingestion_projects p on p.id = bp.project_id
          left join ingestion_platform.ingestion_shipments s on s.id = wi.shipment_id
          where p.project_key = $1
            and bp.target_key = $2
            and wi.status = 'succeeded'
          order by wi.unit_key asc, wi.updated_at desc, wi.id desc
        `,
        [input.projectKey, input.targetKey]
      );

      for (const row of stagingRows.rows) {
        stagingEvidenceByUnitKey[row.unitKey] = {
          status: row.shipmentStatus ?? row.itemStatus,
          shipmentKey: row.shipmentKey ?? undefined,
          shipmentId: row.shipmentId ?? undefined
        };
      }

      const occupiedRows = await client.query<OccupiedRow>(
        `
          select wi.unit_key as "unitKey", wi.status
          from ingestion_platform.ingestion_batch_production_package_wave_items wi
          join ingestion_platform.ingestion_batch_production_package_waves w on w.id = wi.wave_id
          join ingestion_platform.ingestion_batch_plans bp on bp.id = w.batch_plan_id
          join ingestion_platform.ingestion_projects p on p.id = bp.project_id
          where p.project_key = $1
            and bp.target_key = $2
        `,
        [input.projectKey, input.targetKey]
      );
      waveItems.push(...occupiedRows.rows);

      const queueRows = await client.query<OccupiedRow>(
        `
          select qi.unit_key as "unitKey", qi.status
          from ingestion_platform.ingestion_batch_queue_items qi
          join ingestion_platform.ingestion_batch_plans bp on bp.id = qi.batch_plan_id
          join ingestion_platform.ingestion_projects p on p.id = bp.project_id
          where p.project_key = $1
            and bp.target_key = $2
        `,
        [input.projectKey, input.targetKey]
      );
      queueItems.push(
        ...queueRows.rows.map((row) => ({
          unitKey: row.unitKey,
          status: row.status as BatchQueueItemStatus
        }))
      );

      const delivered = await client.query<{ exists: boolean }>(
        `
          select exists (
            select 1
            from ingestion_platform.ingestion_batch_production_package_waves w
            join ingestion_platform.ingestion_batch_plans bp on bp.id = w.batch_plan_id
            join ingestion_platform.ingestion_projects p on p.id = bp.project_id
            where p.project_key = $1
              and bp.target_key = $2
              and w.status in (
                'delivered',
                'consumer_apply_pending',
                'consumer_applied',
                'consumer_apply_failed'
              )
          ) as exists
        `,
        [input.projectKey, input.targetKey]
      );
      hasPriorDeliveredPackage = delivered.rows[0]?.exists === true;
    } catch (error) {
      if (!isUndefinedTable(error)) {
        throw error;
      }
    }

    return {
      stagingEvidenceByUnitKey,
      occupiedUnitKeys: collectOccupiedProductionPackageUnitKeys({ waveItems, queueItems }),
      hasPriorDeliveredPackage
    };
  } finally {
    await closeClient(ownedClient);
  }
}

async function openClient(
  client?: ProductionPackageWaveReadPgClientLike,
  connectionString?: string
): Promise<{ client: ProductionPackageWaveReadPgClientLike; ownedClient?: Client }> {
  if (!client && !connectionString) {
    throw new Error("Production package-wave read requires a server-side connection string or client.");
  }
  const ownedClient = client ? undefined : new Client({ connectionString });
  const resolved = client ?? ownedClient;
  if (!resolved) {
    throw new Error("Production package-wave read client could not be initialized.");
  }
  if (ownedClient) {
    await ownedClient.connect();
  }
  return { client: resolved, ownedClient };
}

async function closeClient(ownedClient?: Client): Promise<void> {
  if (ownedClient) {
    await ownedClient.end();
  }
}

function isUndefinedTable(error: unknown): boolean {
  return (
    typeof error === "object" &&
    error !== null &&
    "code" in error &&
    (error as { code?: string }).code === UNDEFINED_TABLE
  );
}
