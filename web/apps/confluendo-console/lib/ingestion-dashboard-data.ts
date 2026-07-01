import "server-only";

import { loadControlPlaneSnapshot } from "@confluendo/ingestion-platform/control-read";
import {
  buildIngestionDashboardView,
  sampleControlPlaneSnapshot,
  type IngestionDashboardView
} from "@confluendo/ingestion-platform/read-model";

import { loadVamoCacheMetrics } from "./ingestion-cache-stats";

export type IngestionDashboardSource = "live" | "sample";

export interface IngestionDashboardData {
  view: IngestionDashboardView;
  source: IngestionDashboardSource;
}

/**
 * Resolves the dashboard view for the admin console. Operational state comes
 * from the platform control plane; cache-business metrics from the Vamo place
 * cache. Falls back to the bundled sample snapshot when no control DB is
 * configured, the project is unknown, or a read fails — so the console always
 * renders something coherent rather than erroring.
 */
export async function loadIngestionDashboard(
  projectKey = "vamo"
): Promise<IngestionDashboardData> {
  const controlDb = process.env.INGESTION_CONTROL_DATABASE_URL?.trim();
  if (!controlDb) {
    return sample();
  }

  try {
    const snapshot = await loadControlPlaneSnapshot({
      connectionString: controlDb,
      projectKey
    });
    if (!snapshot) {
      return sample();
    }

    const cache = await loadVamoCacheMetrics();
    const merged = cache
      ? { ...snapshot, metrics: { ...snapshot.metrics, ...cache } }
      : snapshot;

    return { view: buildIngestionDashboardView(merged), source: "live" };
  } catch (error) {
    console.error("Ingestion dashboard live read failed; using sample data", error);
    return sample();
  }
}

function sample(): IngestionDashboardData {
  return {
    view: buildIngestionDashboardView(sampleControlPlaneSnapshot),
    source: "sample"
  };
}
