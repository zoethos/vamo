import "server-only";

import { loadProgressiveRunSnapshot } from "@confluendo/ingestion-platform/progressive-control-read";
import {
  buildProgressiveRunView,
  sampleProgressiveRunSnapshot,
  type ProgressiveRunView
} from "@confluendo/ingestion-platform/progressive-read-model";

export type Ip14ProgressiveSource = "live" | "sample" | "error";

export interface Ip14ProgressiveData {
  view: ProgressiveRunView;
  source: Ip14ProgressiveSource;
  error?: string;
}

/**
 * Resolves the IP-14 progressive dry-run board for the admin console. Proposed,
 * scheduled, running, and review-required work comes from the platform control
 * plane (`ingestion_schedule_proposals`) through the same pure read model the
 * sample uses. Missing/empty data falls back to the bundled sample snapshot;
 * live read failures stay visible as `source: "error"` so operators do not
 * mistake an outage for a deliberate preview.
 *
 * Read-path only: this never schedules or executes a run.
 */
export async function loadIp14ProgressiveBoard(
  projectKey = "vamo"
): Promise<Ip14ProgressiveData> {
  const controlDb = process.env.INGESTION_CONTROL_DATABASE_URL?.trim();
  if (!controlDb) {
    return sample();
  }

  try {
    const snapshot = await loadProgressiveRunSnapshot({
      connectionString: controlDb,
      projectKey
    });
    if (!snapshot || snapshot.entries.length === 0) {
      return sample();
    }

    return { view: buildProgressiveRunView(snapshot), source: "live" };
  } catch (error) {
    console.error("IP-14 progressive live read failed", error);
    return {
      ...sample(),
      source: "error",
      error: "Live progressive read failed; showing bundled sample data."
    };
  }
}

function sample(): Ip14ProgressiveData {
  return {
    view: buildProgressiveRunView(sampleProgressiveRunSnapshot),
    source: "sample"
  };
}
