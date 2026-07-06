import "server-only";

import { loadAutonomyDashboard } from "@confluendo/ingestion-platform/autonomy-control-read";
import {
  sampleVamoAutonomyDashboardView,
  type AutonomyDashboardView
} from "@confluendo/ingestion-platform/core";

export type Ip187AutonomySource = "live" | "sample" | "error";

export interface Ip187AutonomyData {
  view: AutonomyDashboardView;
  source: Ip187AutonomySource;
  error?: string;
}

/**
 * Resolves the IP-18.7 autonomy panel for the admin console. Policy/run state
 * comes from persisted control-plane rows when available; otherwise the bundled
 * sample view is used. Missing tables degrade gracefully to sample preview.
 *
 * Read-path only: never executes cycles or mutates control-plane state.
 */
export async function loadIp187Autonomy(projectKey = "vamo"): Promise<Ip187AutonomyData> {
  const controlDb = process.env.INGESTION_CONTROL_DATABASE_URL?.trim();
  if (!controlDb) {
    return sample();
  }

  try {
    const view = await loadAutonomyDashboard({
      connectionString: controlDb,
      projectKey
    });
    if (!view) {
      return sample();
    }
    return { view, source: "live" };
  } catch (error) {
    console.error("IP-18.7 autonomy live read failed", error);
    return {
      ...sample(),
      source: "error",
      error: "Live autonomy read failed; showing bundled sample data."
    };
  }
}

function sample(): Ip187AutonomyData {
  return {
    view: sampleVamoAutonomyDashboardView(),
    source: "sample"
  };
}
