import "server-only";

import { loadBatchQueueSnapshot } from "@confluendo/ingestion-platform/batch-queue-control-read";
import {
  refreshProductionPackageApplyTelemetry,
  sampleVamoEuPoiBatchQueueSnapshot,
  type BatchQueueSnapshot,
  hasActiveSnapshotCommissionRequest,
  loadLatestSnapshotCommissionRequest,
  presentSnapshotCommissionCard,
  type SnapshotCommissionCardPresentation
} from "@confluendo/ingestion-platform/core";
import {
  loadActiveSnapshotReleasePlanBinding,
  toRegisteredSnapshotReleaseSummary
} from "@confluendo/ingestion-platform/core/snapshot-release-plan-binding-read";

export type Ip18BatchQueueSource = "live" | "sample" | "error";

export interface Ip18BatchQueueData {
  snapshot: BatchQueueSnapshot;
  source: Ip18BatchQueueSource;
  error?: string;
  applyTelemetrySource?: "inbox" | "missing";
  registeredSnapshotRelease?: ReturnType<typeof toRegisteredSnapshotReleaseSummary> | null;
  snapshotCommissionCard: SnapshotCommissionCardPresentation;
  snapshotCommissionDefaultCountries: string[];
  snapshotCommissionDefaultCategories: string[];
  snapshotCommissionDefaultMaxRowsPerScope: number;
}

/**
 * Resolves the IP-18 batch queue board for the admin console. Queue state comes
 * from persisted control-plane rows when available; otherwise the bundled Vamo
 * EU POI sample snapshot is used so the dashboard always renders coherently.
 * Missing/empty control-plane data is benign and labeled as sample. Live read
 * failures are labeled as errors so operators do not mistake a broken control
 * database for an intentionally bundled preview.
 *
 * When `VAMO_PRODUCTION_INBOX_TELEMETRY_DATABASE_URL` is set, delivered package
 * waves are enriched with read-only confluendo_inbox apply telemetry.
 *
 * Read-path only: never schedules delivery, executes apply, or mutates inbox rows.
 */
export async function loadIp18BatchQueue(projectKey = "vamo"): Promise<Ip18BatchQueueData> {
  const controlDb = process.env.INGESTION_CONTROL_DATABASE_URL?.trim();
  if (!controlDb) {
    return sample();
  }

  try {
    let snapshot = await loadBatchQueueSnapshot({
      connectionString: controlDb,
      projectKey
    });
    if (!snapshot || snapshot.items.length === 0) {
      return sample();
    }

    const telemetryDb = process.env.VAMO_PRODUCTION_INBOX_TELEMETRY_DATABASE_URL?.trim();
    let applyTelemetrySource: Ip18BatchQueueData["applyTelemetrySource"] = "missing";
    if (telemetryDb) {
      try {
        const refreshed = await refreshProductionPackageApplyTelemetry({
          snapshot,
          controlConnectionString: controlDb,
          telemetryConnectionString: telemetryDb,
          proveTelemetry: () => process.env.VAMO_PRODUCTION_INBOX_ENVIRONMENT === "production",
          syncControl: true
        });
        snapshot = refreshed.snapshot;
        applyTelemetrySource = refreshed.telemetryAvailable ? "inbox" : "missing";
      } catch (error) {
        console.error("Production package apply telemetry refresh failed", error);
      }
    }

    let registeredSnapshotRelease = null;
    let snapshotCommissionCard;
    try {
      const binding = await loadActiveSnapshotReleasePlanBinding({
        connectionString: controlDb,
        projectKey,
        planKey: snapshot.planId
      });
      registeredSnapshotRelease = binding ? toRegisteredSnapshotReleaseSummary(binding) : null;
    } catch (error) {
      console.error("Active snapshot release binding read failed", error);
    }

    const defaultCountries = Object.keys(snapshot.coverage.perCountry).sort();
    const defaultCategories = Object.keys(snapshot.coverage.perCategory).sort();
    const defaultMaxRowsPerScope = 250;

    try {
      const [latestRequest, hasActiveRequest] = await Promise.all([
        loadLatestSnapshotCommissionRequest({
          connectionString: controlDb,
          projectKey,
          planKey: snapshot.planId
        }),
        hasActiveSnapshotCommissionRequest({
          connectionString: controlDb,
          projectKey,
          planKey: snapshot.planId
        })
      ]);
      snapshotCommissionCard = presentSnapshotCommissionCard({
        request: latestRequest,
        hasActiveRequest,
        defaultSourceKey: snapshot.sourceKey,
        defaultCountries,
        defaultCategories,
        defaultMaxRowsPerScope
      });
    } catch (error) {
      console.error("Snapshot commission request read failed", error);
      snapshotCommissionCard = presentSnapshotCommissionCard({
        hasActiveRequest: false,
        defaultSourceKey: snapshot.sourceKey,
        defaultCountries,
        defaultCategories,
        defaultMaxRowsPerScope
      });
    }

    return {
      snapshot,
      source: "live",
      applyTelemetrySource,
      registeredSnapshotRelease,
      snapshotCommissionCard,
      snapshotCommissionDefaultCountries: defaultCountries,
      snapshotCommissionDefaultCategories: defaultCategories,
      snapshotCommissionDefaultMaxRowsPerScope: defaultMaxRowsPerScope
    };
  } catch (error) {
    console.error("IP-18 batch queue live read failed", error);
    return {
      ...sample(),
      source: "error",
      error: "Live batch queue read failed; showing bundled sample data."
    };
  }
}

function sample(): Ip18BatchQueueData {
  const snapshot = sampleVamoEuPoiBatchQueueSnapshot();
  const defaultCountries = Object.keys(snapshot.coverage.perCountry).sort();
  const defaultCategories = Object.keys(snapshot.coverage.perCategory).sort();
  const defaultMaxRowsPerScope = 250;
  return {
    snapshot,
    source: "sample",
    snapshotCommissionCard: presentSnapshotCommissionCard({
      hasActiveRequest: false,
      defaultSourceKey: snapshot.sourceKey,
      defaultCountries,
      defaultCategories,
      defaultMaxRowsPerScope
    }),
    snapshotCommissionDefaultCountries: defaultCountries,
    snapshotCommissionDefaultCategories: defaultCategories,
    snapshotCommissionDefaultMaxRowsPerScope: defaultMaxRowsPerScope
  };
}
