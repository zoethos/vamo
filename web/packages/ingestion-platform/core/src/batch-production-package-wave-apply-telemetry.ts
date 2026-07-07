/**
 * Production package-wave apply telemetry orchestration (IP-18.6.4).
 *
 * Reads inbox apply status with a telemetry credential, optionally mirrors it
 * into the control DB, and enriches batch queue snapshots for dashboard use.
 */

import { Client } from "pg";

import { readPostgresProductionInboxApplyTelemetry } from "../../adapters/target/src/postgres-production-inbox-telemetry.js";
import { syncProductionPackageWaveApplyTelemetry } from "./batch-production-package-wave-apply-telemetry-control.js";
import { loadProductionPackageWave } from "./batch-production-package-wave-load.js";
import type { BatchQueueSnapshot } from "./batch-queue-read-model.js";
import {
  collectDeliveredProductionPackageIds,
  enrichBatchQueueSnapshotWithApplyTelemetry,
  mapProductionInboxApplyTelemetryByPackageId
} from "./production-package-wave-apply-telemetry.js";

export interface RefreshProductionPackageApplyTelemetryInput {
  snapshot: BatchQueueSnapshot;
  controlConnectionString?: string;
  telemetryConnectionString?: string;
  proveTelemetry?: () => boolean | Promise<boolean>;
  syncControl?: boolean;
  now?: string;
}

export interface RefreshProductionPackageApplyTelemetryResult {
  snapshot: BatchQueueSnapshot;
  telemetryAvailable: boolean;
  telemetryPackageCount: number;
  syncedControl: boolean;
}

export async function refreshProductionPackageApplyTelemetry(
  input: RefreshProductionPackageApplyTelemetryInput
): Promise<RefreshProductionPackageApplyTelemetryResult> {
  const telemetryConnectionString = input.telemetryConnectionString?.trim();
  const wave = input.snapshot.latestProductionPackageWave;
  const packageIds = collectDeliveredProductionPackageIds(wave);

  if (!wave || packageIds.length === 0 || !telemetryConnectionString) {
    return {
      snapshot: input.snapshot,
      telemetryAvailable: false,
      telemetryPackageCount: 0,
      syncedControl: false
    };
  }

  const telemetry = await readPostgresProductionInboxApplyTelemetry({
    connectionString: telemetryConnectionString,
    packageIds,
    proveTelemetry: input.proveTelemetry
  });

  if (!telemetry.ok) {
    return {
      snapshot: input.snapshot,
      telemetryAvailable: false,
      telemetryPackageCount: 0,
      syncedControl: false
    };
  }

  const telemetryByPackageId = mapProductionInboxApplyTelemetryByPackageId(telemetry.packages);
  let syncedControl = false;

  if (input.syncControl !== false && input.controlConnectionString?.trim()) {
    const loadedWave = await loadProductionPackageWave({
      connectionString: input.controlConnectionString,
      projectKey: input.snapshot.projectKey,
      waveKey: wave.waveKey
    });
    if (loadedWave) {
      await syncProductionPackageWaveApplyTelemetry({
        connectionString: input.controlConnectionString,
        waveId: loadedWave.id,
        batchPlanId: loadedWave.batchPlanId,
        telemetryByPackageId,
        now: input.now
      });
      syncedControl = true;
    }
  }

  return {
    snapshot: enrichBatchQueueSnapshotWithApplyTelemetry({
      snapshot: input.snapshot,
      telemetryByPackageId,
      telemetryAvailable: true
    }),
    telemetryAvailable: true,
    telemetryPackageCount: telemetry.packages.length,
    syncedControl
  };
}

export async function withProductionPackageApplyTelemetryClient<T>(
  connectionString: string,
  run: (client: Client) => Promise<T>
): Promise<T> {
  const client = new Client({ connectionString });
  await client.connect();
  try {
    return await run(client);
  } finally {
    await client.end();
  }
}
