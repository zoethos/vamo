/**
 * Persist observed production inbox apply telemetry into the Confluendo control DB.
 *
 * Reads inbox evidence elsewhere; this module only mirrors observed apply status
 * into control-plane wave, wave-item, and queue rows. Never writes to the inbox
 * or Vamo product tables.
 */

import { Client, type QueryResult } from "pg";

import type { MappedProductionPackageApplyTelemetry } from "./production-package-wave-apply-telemetry.js";

export interface BatchProductionPackageApplyTelemetryControlPgClientLike {
  query<T extends Record<string, unknown> = Record<string, unknown>>(
    sql: string,
    values?: unknown[]
  ): Promise<QueryResult<T>>;
}

export interface SyncProductionPackageWaveApplyTelemetryInput {
  connectionString?: string;
  client?: BatchProductionPackageApplyTelemetryControlPgClientLike;
  waveId: string;
  batchPlanId: string;
  telemetryByPackageId: Readonly<Record<string, MappedProductionPackageApplyTelemetry>>;
  now?: string;
}

export interface SyncProductionPackageWaveApplyTelemetryResult {
  ok: true;
  updatedWave: boolean;
  updatedItems: number;
  updatedQueueItems: number;
}

interface WaveItemRow extends Record<string, unknown> {
  id: string;
  unitKey: string;
  packageId: string | null;
  packageKey: string | null;
  status: string;
}

export async function syncProductionPackageWaveApplyTelemetry(
  input: SyncProductionPackageWaveApplyTelemetryInput
): Promise<SyncProductionPackageWaveApplyTelemetryResult> {
  const { client, ownedClient } = await openClient(input.client, input.connectionString);
  const now = input.now ?? new Date().toISOString();
  const entries = Object.values(input.telemetryByPackageId);
  if (entries.length === 0) {
    await closeClient(ownedClient);
    return { ok: true, updatedWave: false, updatedItems: 0, updatedQueueItems: 0 };
  }

  try {
    await client.query("begin");
    await client.query("set local statement_timeout = '10s'");

    const waveItems = await client.query<WaveItemRow>(
      `
        select
          id::text as id,
          unit_key as "unitKey",
          package_id as "packageId",
          package_key as "packageKey",
          status
        from ingestion_platform.ingestion_batch_production_package_wave_items
        where wave_id = $1::bigint
        order by run_order asc, unit_key asc
      `,
      [input.waveId]
    );

    let updatedItems = 0;
    let updatedQueueItems = 0;

    for (const item of waveItems.rows) {
      const packageId = item.packageId ?? item.packageKey;
      if (!packageId) {
        continue;
      }
      const mapped = input.telemetryByPackageId[packageId];
      if (!mapped || item.status === mapped.waveItemStatus) {
        continue;
      }

      await client.query(
        `
          update ingestion_platform.ingestion_batch_production_package_wave_items
          set status = $2,
              apply_evidence = $3::jsonb,
              updated_at = $4::timestamptz
          where id = $1::bigint
        `,
        [item.id, mapped.waveItemStatus, JSON.stringify(mapped.evidence), now]
      );
      updatedItems += 1;

      const queueUpdate = await client.query(
        `
          update ingestion_platform.ingestion_batch_queue_items
          set status = $3,
              updated_at = $4::timestamptz
          where batch_plan_id = $1::bigint
            and unit_key = $2
            and status in (
              'production_package_delivered',
              'consumer_apply_pending',
              'consumer_applied',
              'consumer_apply_failed'
            )
        `,
        [input.batchPlanId, item.unitKey, mapped.queueItemStatus, now]
      );
      updatedQueueItems += queueUpdate.rowCount ?? 0;
    }

    const aggregate = aggregateMappedTelemetry(entries);
    const waveUpdate = await client.query(
      `
        update ingestion_platform.ingestion_batch_production_package_waves
        set status = $2,
            consumer_apply_status = $3,
            consumer_apply_evidence = $4::jsonb,
            updated_at = $5::timestamptz
        where id = $1::bigint
          and status in ('delivered', 'consumer_apply_pending', 'consumer_applied', 'consumer_apply_failed')
      `,
      [
        input.waveId,
        aggregate.waveStatus,
        aggregate.consumerApplyStatus,
        JSON.stringify(aggregate.evidence),
        now
      ]
    );

    await client.query("commit");
    return {
      ok: true,
      updatedWave: (waveUpdate.rowCount ?? 0) > 0,
      updatedItems,
      updatedQueueItems
    };
  } catch (error) {
    await client.query("rollback");
    throw error;
  } finally {
    await closeClient(ownedClient);
  }
}

function aggregateMappedTelemetry(entries: MappedProductionPackageApplyTelemetry[]): {
  waveStatus: string;
  consumerApplyStatus: string;
  evidence: Record<string, unknown>;
} {
  const hasFailed = entries.some((entry) => entry.consumerApplyStatus === "failed");
  const hasPending = entries.some((entry) => entry.consumerApplyStatus === "pending");
  const allApplied = entries.every((entry) => entry.consumerApplyStatus === "applied");

  let waveStatus = "delivered";
  let consumerApplyStatus = "unknown";
  if (hasFailed) {
    waveStatus = "consumer_apply_failed";
    consumerApplyStatus = "failed";
  } else if (allApplied) {
    waveStatus = "consumer_applied";
    consumerApplyStatus = "applied";
  } else if (hasPending) {
    waveStatus = "consumer_apply_pending";
    consumerApplyStatus = "pending";
  }

  return {
    waveStatus,
    consumerApplyStatus,
    evidence: {
      source: "confluendo_inbox",
      syncedAt: new Date().toISOString(),
      packages: entries.map((entry) => ({
        packageId: entry.packageId,
        consumerApplyStatus: entry.consumerApplyStatus,
        evidence: entry.evidence
      }))
    }
  };
}

async function openClient(
  client?: BatchProductionPackageApplyTelemetryControlPgClientLike,
  connectionString?: string
): Promise<{
  client: BatchProductionPackageApplyTelemetryControlPgClientLike;
  ownedClient?: Client;
}> {
  if (!client && !connectionString) {
    throw new Error("Production package apply telemetry sync requires a server-side connection string or client.");
  }
  const ownedClient = client ? undefined : new Client({ connectionString });
  const resolved = client ?? ownedClient;
  if (!resolved) {
    throw new Error("Production package apply telemetry sync client could not be initialized.");
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
