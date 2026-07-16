import "server-only";

import { loadBatchQueueSnapshot } from "@confluendo/ingestion-platform/batch-queue-control-read";
import {
  refreshProductionPackageApplyTelemetry,
  sampleVamoEuPoiBatchQueueSnapshot,
  type BatchQueueSnapshot,
  hasActiveSnapshotCommissionRequest,
  hasActiveSnapshotActivationRequest,
  loadBatchPlanSourceTaxonomyState,
  loadLatestSnapshotActivationRequest,
  loadLatestSnapshotCommissionRequest,
  presentBatchPlanContractRefreshCard,
  presentSnapshotActivationCard,
  presentSnapshotCommissionCard,
  type BatchPlanContractRefreshCardPresentation,
  type SnapshotActivationCardPresentation,
  type SnapshotCommissionCardPresentation
} from "@confluendo/ingestion-platform/core";
import {
  loadActiveSnapshotReleasePlanBinding,
  toRegisteredSnapshotReleaseSummary
} from "@confluendo/ingestion-platform/core/snapshot-release-plan-binding-read";
import { getActiveControlEnvironmentConfig } from "./control-environment-server";

export type Ip18BatchQueueSource = "live" | "sample" | "error";

export interface Ip18BatchQueueData {
  snapshot: BatchQueueSnapshot;
  source: Ip18BatchQueueSource;
  error?: string;
  applyTelemetrySource?: "inbox" | "missing";
  registeredSnapshotRelease?: ReturnType<typeof toRegisteredSnapshotReleaseSummary> | null;
  snapshotCommissionCard: SnapshotCommissionCardPresentation;
  snapshotActivationCard: SnapshotActivationCardPresentation;
  planContractRefreshCard: BatchPlanContractRefreshCardPresentation;
  snapshotCommissionDefaultCountries: string[];
  snapshotCommissionDefaultCategories: string[];
  snapshotCommissionDefaultMaxRowsPerScope: number;
}

const CONSOLE_LIVE_READ_DEADLINE_MS = 5_000;

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
  const environmentConfig = await getActiveControlEnvironmentConfig();
  const controlDb = environmentConfig?.controlDatabaseUrl;
  if (!controlDb) {
    return sample();
  }

  try {
    const loadedSnapshot = await withConsoleLiveReadDeadline("Batch queue", () =>
      loadBatchQueueSnapshot({
        connectionString: controlDb,
        projectKey
      })
    );
    if (!loadedSnapshot || loadedSnapshot.items.length === 0) {
      return sample();
    }
    let snapshot: BatchQueueSnapshot = loadedSnapshot;

    const telemetryDb = environmentConfig?.vamoProductionInboxTelemetryDatabaseUrl;
    let applyTelemetrySource: Ip18BatchQueueData["applyTelemetrySource"] = "missing";
    if (telemetryDb) {
      try {
        const refreshed = await withConsoleLiveReadDeadline("Consumer inbox telemetry", () =>
          refreshProductionPackageApplyTelemetry({
            snapshot,
            controlConnectionString: controlDb,
            telemetryConnectionString: telemetryDb,
            proveTelemetry: () => environmentConfig?.vamoProductionInboxEnvironment === "production",
            syncControl: false
          })
        );
        snapshot = refreshed.snapshot;
        applyTelemetrySource = refreshed.telemetryAvailable ? "inbox" : "missing";
      } catch (error) {
        console.error("Production package apply telemetry refresh failed", error);
      }
    }

    let registeredSnapshotRelease = null;
    let snapshotCommissionCard;
    let snapshotActivationCard;
    let planContractRefreshCard: BatchPlanContractRefreshCardPresentation;
    try {
      const binding = await withConsoleLiveReadDeadline("Active source release", () =>
        loadActiveSnapshotReleasePlanBinding({
          connectionString: controlDb,
          projectKey,
          planKey: snapshot.planId
        })
      );
      registeredSnapshotRelease = binding ? toRegisteredSnapshotReleaseSummary(binding) : null;
    } catch (error) {
      console.error("Active snapshot release binding read failed", error);
    }

    const defaultCountries = Object.keys(snapshot.coverage.perCountry).sort();
    const defaultCategories = Object.keys(snapshot.coverage.perCategory).sort();
    const defaultMaxRowsPerScope = 250;

    try {
      const planContract = await withConsoleLiveReadDeadline("Plan source mapping", () =>
        loadBatchPlanSourceTaxonomyState({
          connectionString: controlDb,
          projectKey,
          planKey: snapshot.planId
        })
      );
      planContractRefreshCard = presentBatchPlanContractRefreshCard({
        projectKey: planContract?.projectKey ?? snapshot.projectKey,
        planKey: planContract?.planKey ?? snapshot.planId,
        sourceKey: planContract?.sourceKey ?? snapshot.sourceKey,
        currentSourceTaxonomy: planContract?.sourceTaxonomy,
        liveControlPlane: Boolean(planContract)
      });
    } catch (error) {
      console.error("Plan source mapping read failed", error);
      planContractRefreshCard = presentBatchPlanContractRefreshCard({
        projectKey: snapshot.projectKey,
        planKey: snapshot.planId,
        sourceKey: snapshot.sourceKey,
        liveControlPlane: false
      });
    }

    try {
      const [latestRequest, hasActiveRequest, latestActivationRequest, hasActiveActivationRequest] =
        await withConsoleLiveReadDeadline("Source release request state", () =>
          Promise.all([
            loadLatestSnapshotCommissionRequest({
              connectionString: controlDb,
              projectKey,
              planKey: snapshot.planId
            }),
            hasActiveSnapshotCommissionRequest({
              connectionString: controlDb,
              projectKey,
              planKey: snapshot.planId
            }),
            loadLatestSnapshotActivationRequest({
              connectionString: controlDb,
              projectKey,
              planKey: snapshot.planId
            }),
            hasActiveSnapshotActivationRequest({
              connectionString: controlDb,
              projectKey,
              planKey: snapshot.planId
            })
          ])
        );
      snapshotCommissionCard = presentSnapshotCommissionCard({
        request: latestRequest,
        hasActiveRequest,
        defaultSourceKey: snapshot.sourceKey,
        defaultCountries,
        defaultCategories,
        defaultMaxRowsPerScope,
        sourceTaxonomyReady: planContractRefreshCard.statusLabel === "Configured"
      });
      snapshotActivationCard = presentSnapshotActivationCard({
        commissionRequest: latestRequest,
        activationRequest: latestActivationRequest,
        hasActiveRequest: hasActiveActivationRequest
      });
    } catch (error) {
      console.error("Snapshot commissioning or activation request read failed", error);
      snapshotCommissionCard = presentSnapshotCommissionCard({
        hasActiveRequest: false,
        defaultSourceKey: snapshot.sourceKey,
        defaultCountries,
        defaultCategories,
        defaultMaxRowsPerScope,
        sourceTaxonomyReady: planContractRefreshCard.statusLabel === "Configured"
      });
      snapshotActivationCard = presentSnapshotActivationCard({ hasActiveRequest: false });
    }

    return {
      snapshot,
      source: "live",
      applyTelemetrySource,
      registeredSnapshotRelease,
      snapshotCommissionCard,
      snapshotActivationCard,
      planContractRefreshCard,
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
    snapshotActivationCard: presentSnapshotActivationCard({ hasActiveRequest: false }),
    planContractRefreshCard: presentBatchPlanContractRefreshCard({
      projectKey: snapshot.projectKey,
      planKey: snapshot.planId,
      sourceKey: snapshot.sourceKey,
      liveControlPlane: false
    }),
    snapshotCommissionDefaultCountries: defaultCountries,
    snapshotCommissionDefaultCategories: defaultCategories,
    snapshotCommissionDefaultMaxRowsPerScope: defaultMaxRowsPerScope
  };
}

async function withConsoleLiveReadDeadline<T>(label: string, read: () => Promise<T>): Promise<T> {
  let timeout: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([
      read(),
      new Promise<never>((_, reject) => {
        timeout = setTimeout(
          () => reject(new Error(`${label} did not respond within ${CONSOLE_LIVE_READ_DEADLINE_MS / 1000}s.`)),
          CONSOLE_LIVE_READ_DEADLINE_MS
        );
      })
    ]);
  } finally {
    if (timeout) {
      clearTimeout(timeout);
    }
  }
}
