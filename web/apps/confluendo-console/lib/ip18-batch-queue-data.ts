import "server-only";

import { loadBatchQueueSnapshot } from "@confluendo/ingestion-platform/batch-queue-control-read";
import {
  sampleVamoEuPoiBatchQueueSnapshot,
  type BatchQueueSnapshot
} from "@confluendo/ingestion-platform/core";

export type Ip18BatchQueueSource = "live" | "sample";

export interface Ip18BatchQueueData {
  snapshot: BatchQueueSnapshot;
  source: Ip18BatchQueueSource;
}

/**
 * Resolves the IP-18 batch queue board for the admin console. Queue state comes
 * from persisted control-plane rows when available; otherwise the bundled Vamo
 * EU POI sample snapshot is used so the dashboard always renders coherently.
 *
 * Read-path only: never schedules, executes, or mutates queue rows.
 */
export async function loadIp18BatchQueue(projectKey = "vamo"): Promise<Ip18BatchQueueData> {
  const controlDb = process.env.INGESTION_CONTROL_DATABASE_URL?.trim();
  if (!controlDb) {
    return sample();
  }

  try {
    const snapshot = await loadBatchQueueSnapshot({
      connectionString: controlDb,
      projectKey
    });
    if (!snapshot || snapshot.items.length === 0) {
      return sample();
    }

    return { snapshot, source: "live" };
  } catch (error) {
    console.error("IP-18 batch queue live read failed; using sample data", error);
    return sample();
  }
}

function sample(): Ip18BatchQueueData {
  return {
    snapshot: sampleVamoEuPoiBatchQueueSnapshot(),
    source: "sample"
  };
}
