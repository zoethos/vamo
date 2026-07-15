import "server-only";

import { Client } from "pg";
import { getActiveControlEnvironmentConfig } from "./control-environment-server";
import { loadAutonomyDashboard, loadAutonomyPolicy } from "@confluendo/ingestion-platform/autonomy-control-read";
import { loadBatchQueueSnapshot } from "@confluendo/ingestion-platform/batch-queue-control-read";
import {
  loadAutonomyRampReadiness,
  createBoundedPostgresReadClientConfig,
  presentAutonomyProductionHandoffCard,
  presentAutonomyRampCard,
  sampleVamoAutonomyDashboardView,
  type AutonomyDashboardView,
  type AutonomyProductionHandoffCardPresentation,
  type AutonomyRampCardPresentation
} from "@confluendo/ingestion-platform/core";

export type Ip187AutonomySource = "live" | "sample" | "error";

export interface Ip187AutonomyData {
  view: AutonomyDashboardView;
  rampCard: AutonomyRampCardPresentation | null;
  productionHandoffCard: AutonomyProductionHandoffCardPresentation | null;
  policyKey: string | null;
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
  const controlDb = (await getActiveControlEnvironmentConfig())?.controlDatabaseUrl;
  if (!controlDb) {
    return sample();
  }

  const client = new Client(createBoundedPostgresReadClientConfig(controlDb));
  try {
    await client.connect();
    const view = await loadAutonomyDashboard({
      client,
      projectKey
    });
    if (!view?.policy) {
      return sample();
    }

    const policy = await loadAutonomyPolicy(client, {
      projectKey,
      policyKey: view.policy.policyKey
    });
    if (!policy) {
      return {
        view,
        rampCard: null,
        productionHandoffCard: null,
        policyKey: view.policy.policyKey,
        source: "live"
      };
    }

    const [queueSnapshot, readiness] = await Promise.all([
      loadBatchQueueSnapshot({ client, projectKey, targetKey: policy.targetKey }),
      loadAutonomyRampReadiness({
        client,
        projectKey,
        policyKey: policy.policyKey
      })
    ]);

    const rampCard = presentAutonomyRampCard({
      policy,
      readiness,
      blockerSummaries: queueSnapshot?.blockerSummaries ?? [],
      blockedUnitCount: queueSnapshot?.progress.blocked ?? 0
    });
    const productionHandoffCard = presentAutonomyProductionHandoffCard(policy);

    return {
      view,
      rampCard,
      productionHandoffCard,
      policyKey: policy.policyKey,
      source: "live"
    };
  } catch (error) {
    console.error("IP-18.7 autonomy live read failed", error);
    return {
      ...sample(),
      source: "error",
      error: "Live autonomy read failed; showing bundled sample data."
    };
  } finally {
    await client.end();
  }
}

function sample(): Ip187AutonomyData {
  const view = sampleVamoAutonomyDashboardView();
  const policyKey = view.policy?.policyKey ?? "vamo-eu-poi-staging";
  const samplePolicy = view.policy
    ? {
        policyId: view.policy.policyId,
        policyKey: view.policy.policyKey,
        projectKey: view.projectKey,
        sourceKey: view.policy.sourceKey,
        targetKey: view.policy.targetKey,
        targetEnvironment: view.policy.targetEnvironment as "staging",
        status: view.policy.status as "active",
        allowedTiers: [],
        allowedGeographies: [],
        allowedCategories: [],
        allowedTransitions: ["schedule_dry_run", "execute_dry_run", "approve_staging_wave"],
        maxUnitsPerCycle: view.policy.maxUnitsPerCycle,
        maxRowsPerCycle: view.policy.maxRowsPerCycle,
        rollingLimits: view.policy.rampProfile.rollingLimits,
        guardThresholds: {},
        productionInboxHandoffPolicy: { requiresIp18_6: true },
        policyVersion: view.policy.policyVersion,
        rampMode: view.policy.rampMode,
        summary: view.policy.summary
      }
    : null;
  return {
    view,
    rampCard: samplePolicy
      ? presentAutonomyRampCard({
          policy: samplePolicy,
          readiness: {
            policyId: samplePolicy.policyId,
            policyKey: samplePolicy.policyKey,
            currentMode: samplePolicy.rampMode,
            since: new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString(),
            runs: { advanced: 2, completed: 1, failed: 0, paused: 0 },
            stagingCanarySucceededUnits: 0
          },
          blockerSummaries: [],
          blockedUnitCount: 0
        })
      : null,
    productionHandoffCard: samplePolicy ? presentAutonomyProductionHandoffCard(samplePolicy) : null,
    policyKey,
    source: "sample"
  };
}
