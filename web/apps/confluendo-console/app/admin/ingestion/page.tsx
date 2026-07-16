import type { Metadata } from "next";
import {
  STAGING_CANARY_FRESH_STEP_UP_WINDOW_MS,
  countStagingProvenPackageEligibleUnits,
  describeProductionPackageContentEquivalence,
  describeProductionPackageWaveStatus,
  loadProductionPackageWaveApprovalContext
} from "@confluendo/ingestion-platform/core";
import { loadIp18BatchQueue } from "@/lib/ip18-batch-queue-data";
import { loadIp187Autonomy } from "@/lib/ip18-autonomy-data";
import { requireIngestionDashboardAccess } from "@/lib/ingestion-admin-auth";
import { loadIngestionDashboard } from "@/lib/ingestion-dashboard-data";
import { loadIp14ProgressiveBoard } from "@/lib/ip14-progressive-data";
import { CONTROL_ENVIRONMENTS } from "@/lib/control-environment";
import {
  getControlEnvironmentConfig,
  getDefaultControlEnvironment
} from "@/lib/control-environment-config";
import { getActiveControlEnvironmentConfig } from "@/lib/control-environment-server";
import { IngestionConsoleShell } from "./ingestion-console-shell";
import {
  isActionableWorkflowAttentionItem
} from "@confluendo/ingestion-platform/core/workflow-navigator-presenter";
import {
  percentOf,
  queueStatusTones
} from "./ingestion-console-labels";

export const metadata: Metadata = {
  title: "Ingestion control · Confluendo",
  robots: {
    index: false,
    follow: false
  }
};

export const dynamic = "force-dynamic";

const CONSOLE_READ_DEADLINE_MS = 5_000;

export default async function IngestionDashboardPage() {
  const environmentConfig = await getActiveControlEnvironmentConfig();
  const controlEnvironment = environmentConfig?.environment ?? getDefaultControlEnvironment();
  const availableControlEnvironments = CONTROL_ENVIRONMENTS.filter((environment) =>
    Boolean(getControlEnvironmentConfig(environment))
  );
  const principal = await requireIngestionDashboardAccess({
    projectKey: "vamo",
    nextPath: "/admin/ingestion"
  });
  const serverNowMs = Date.now();
  const freshStepUpExpiresAt = freshStepUpExpiry(principal.stepUpSatisfiedAt);

  const [
    { view, source },
    { view: progressiveView, source: progressiveSource },
    batchQueueData,
    autonomyData
  ] = await Promise.all([
    loadIngestionDashboard("vamo"),
    loadIp14ProgressiveBoard("vamo"),
    loadIp18BatchQueue("vamo"),
    loadIp187Autonomy("vamo")
  ]);
  const {
    signals: ingestionSignals,
    actions: ingestionActions,
    instances: ingestionInstances,
    targets: ingestionTargets,
    events: ingestionEvents,
    stats: ingestionStats,
    policyLocks: ingestionPolicyLocks
  } = view;

  const {
    snapshot: batchQueue,
    source: batchQueueSource,
    error: batchQueueError,
    applyTelemetrySource,
    registeredSnapshotRelease,
    snapshotCommissionCard,
    snapshotActivationCard,
    planContractRefreshCard,
    snapshotCommissionDefaultCountries,
    snapshotCommissionDefaultCategories,
    snapshotCommissionDefaultMaxRowsPerScope
  } = batchQueueData;
  const {
    view: autonomyView,
    rampCard,
    productionHandoffCard,
    policyKey: autonomyPolicyKey,
    source: autonomySource,
    error: autonomyError
  } = autonomyData;

  const batchCategories = Object.keys(batchQueue.coverage.perCategory).sort();
  const batchCountries = Object.keys(batchQueue.coverage.perCountry).sort();
  const batchQueueEligibleCount = batchQueue.items.filter(
    (item) => item.status === "ready_for_dry_run"
  ).length;
  const batchCanaryWaveEligibleCount = batchQueue.progress.stagingCanary.dryRunSucceededEligible;

  let productionPackageEligibleCount = 0;
  let productionPackageOccupiedUnitKeys: string[] = [];
  let productionPackageStagingEvidenceByUnitKey: Record<string, { status?: string }> = {};
  let productionPackageHasPriorDeliveredPackage = false;
  if (batchQueueSource === "live") {
    const controlDb = environmentConfig?.controlDatabaseUrl;
    if (controlDb) {
      try {
        const packageContext = await withConsoleReadDeadline(
          "Production package context",
          () =>
            loadProductionPackageWaveApprovalContext({
              connectionString: controlDb,
              projectKey: batchQueue.projectKey,
              targetKey: batchQueue.targetKey
            })
        );
        productionPackageEligibleCount = countStagingProvenPackageEligibleUnits(
          batchQueue,
          batchQueue.targetKey,
          packageContext.stagingEvidenceByUnitKey,
          packageContext.occupiedUnitKeys
        );
        productionPackageOccupiedUnitKeys = [...packageContext.occupiedUnitKeys];
        productionPackageStagingEvidenceByUnitKey = packageContext.stagingEvidenceByUnitKey;
        productionPackageHasPriorDeliveredPackage = packageContext.hasPriorDeliveredPackage;
      } catch (error) {
        console.error("Production package-wave context read failed", error);
      }
    }
  }

  const latestProductionPackageWave = batchQueue.latestProductionPackageWave
    ? {
        waveKey: batchQueue.latestProductionPackageWave.waveKey,
        status: batchQueue.latestProductionPackageWave.status,
        schemaContract: batchQueue.latestProductionPackageWave.schemaContract,
        approvalExpiresAt: batchQueue.latestProductionPackageWave.approvalExpiresAt,
        consumerApplyStatus: batchQueue.latestProductionPackageWave.consumerApplyStatus,
        telemetrySource: batchQueue.latestProductionPackageWave.telemetrySource,
        packageId: batchQueue.latestProductionPackageWave.packageId,
        items: batchQueue.latestProductionPackageWave.items?.map((item) => {
          const contentEquivalence = describeProductionPackageContentEquivalence({
            stagingEvidence: undefined,
            itemStatus: item.status,
            blockers: item.blockers
          });
          return {
          unitKey: item.unitKey,
          runOrder: item.runOrder,
          status: item.status,
          packageId: item.packageId ?? item.packageKey,
          consumerApplyStatus: item.consumerApplyStatus,
          telemetrySource: item.telemetrySource,
          contentEquivalenceLabel: item.contentEquivalenceLabel ?? contentEquivalence.label,
          contentEquivalenceStatus: item.contentEquivalenceStatus ?? contentEquivalence.status,
          statusPresentation: describeProductionPackageWaveStatus(
            item.consumerApplyStatus === "applied"
              ? "consumer_applied"
              : item.consumerApplyStatus === "failed"
                ? "consumer_apply_failed"
                : item.consumerApplyStatus === "pending"
                  ? "consumer_apply_pending"
                  : item.status
          )
        };
        }),
        statusPresentation: describeProductionPackageWaveStatus(
          batchQueue.latestProductionPackageWave.status
        )
      }
    : null;

  const attentionRows = batchQueue.items
    .filter(
      (item) =>
        (queueStatusTones[item.status] === "danger" || item.blockReasons.length > 0) &&
        isActionableWorkflowAttentionItem(item)
    )
    .slice(0, 6);

  const operatorHealth =
    attentionRows.length > 0
      ? {
          title: `${attentionRows.length} scope${attentionRows.length === 1 ? "" : "s"} need attention`,
          detail:
            "The agent can continue everything else inside policy, but these scopes need operator review.",
          tone: "watch" as const
        }
      : {
          title: "Healthy",
          detail: "No queue exceptions are active. The platform can keep advancing bounded work.",
          tone: "good" as const
        };

  const operatorNextAction =
    autonomyView.nextCycle.recommendedAction?.summary ??
    (productionPackageEligibleCount > 0
      ? "Approve the next consumer inbox delivery batch when the current evidence looks right."
      : batchQueue.nextAction);

  const pipelineMetrics = [
    {
      label: "Ready to simulate",
      value: batchQueue.progress.ready + batchQueue.progress.execution.dryRunReady,
      detail: "Scopes waiting for the agent's simulation step.",
      tone: "info" as const
    },
    {
      label: "Simulation passed",
      value: batchQueue.progress.execution.dryRunSucceeded,
      detail: "Safe simulation evidence with no target writes.",
      tone: "good" as const
    },
    {
      label: "Staging verified",
      value: batchQueue.progress.stagingCanary.succeeded,
      detail: "Consumer-shaped writes proven in staging.",
      tone: "good" as const
    },
    {
      label: "Delivered to inbox",
      value:
        batchQueue.progress.productionPackage.delivered +
        batchQueue.progress.productionPackage.applyPending +
        batchQueue.progress.productionPackage.applied +
        batchQueue.progress.productionPackage.applyFailed,
      detail: "Delivery packages handed to the consumer inbox.",
      tone: "info" as const
    },
    {
      label: "Applied by consumer",
      value: batchQueue.progress.productionPackage.applied,
      detail: "Consumer confirmed product-table apply.",
      tone: "good" as const
    },
    {
      label: "Needs attention",
      value:
        batchQueue.progress.blocked +
        batchQueue.progress.execution.dryRunBlocked +
        batchQueue.progress.stagingCanary.blocked +
        batchQueue.progress.productionPackage.blocked +
        batchQueue.progress.productionPackage.applyFailed,
      detail: "Blocked, failed, or outside current policy.",
      tone: attentionRows.length > 0 ? ("danger" as const) : ("neutral" as const)
    }
  ];

  const deliveryTotal = Math.max(
    1,
    batchQueue.progress.productionPackage.delivered +
      batchQueue.progress.productionPackage.applyPending +
      batchQueue.progress.productionPackage.applied +
      batchQueue.progress.productionPackage.applyFailed
  );
  const deliverySplit = [
    {
      label: "Delivered only",
      value: batchQueue.progress.productionPackage.delivered,
      percent: percentOf(batchQueue.progress.productionPackage.delivered, deliveryTotal),
      tone: "info" as const
    },
    {
      label: "Waiting for apply",
      value: batchQueue.progress.productionPackage.applyPending,
      percent: percentOf(batchQueue.progress.productionPackage.applyPending, deliveryTotal),
      tone: "watch" as const
    },
    {
      label: "Applied by consumer",
      value: batchQueue.progress.productionPackage.applied,
      percent: percentOf(batchQueue.progress.productionPackage.applied, deliveryTotal),
      tone: "good" as const
    },
    {
      label: "Apply failed",
      value: batchQueue.progress.productionPackage.applyFailed,
      percent: percentOf(batchQueue.progress.productionPackage.applyFailed, deliveryTotal),
      tone: "danger" as const
    }
  ];

  const coverageRows = batchCountries.map((country) => ({
    country,
    cells: batchCategories.map((category) => ({
      category,
      value: batchQueue.coverage.matrix[country]?.[category] ?? 0
    }))
  }));

  return (
    <IngestionConsoleShell
      principal={principal}
      freshStepUpExpiresAt={freshStepUpExpiresAt}
      serverNowMs={serverNowMs}
      source={source}
      ingestionSignals={ingestionSignals}
      ingestionActions={ingestionActions}
      ingestionInstances={ingestionInstances}
      ingestionTargets={ingestionTargets}
      ingestionEvents={ingestionEvents}
      ingestionStats={ingestionStats}
      ingestionPolicyLocks={ingestionPolicyLocks}
      progressiveView={progressiveView}
      progressiveSource={progressiveSource}
      batchQueue={batchQueue}
      batchQueueSource={batchQueueSource}
      batchQueueError={batchQueueError}
      applyTelemetrySource={applyTelemetrySource}
      autonomyView={autonomyView}
      autonomySource={autonomySource}
      autonomyError={autonomyError}
      rampCard={rampCard}
      productionHandoffCard={productionHandoffCard}
      autonomyPolicyKey={autonomyPolicyKey}
      batchCategories={batchCategories}
      batchCountries={batchCountries}
      batchQueueEligibleCount={batchQueueEligibleCount}
      batchCanaryWaveEligibleCount={batchCanaryWaveEligibleCount}
      productionPackageEligibleCount={productionPackageEligibleCount}
      productionPackageOccupiedUnitKeys={productionPackageOccupiedUnitKeys}
      productionPackageStagingEvidenceByUnitKey={productionPackageStagingEvidenceByUnitKey}
      productionPackageHasPriorDeliveredPackage={productionPackageHasPriorDeliveredPackage}
      latestProductionPackageWave={latestProductionPackageWave}
      registeredSnapshotRelease={registeredSnapshotRelease}
      snapshotCommissionCard={snapshotCommissionCard}
      snapshotActivationCard={snapshotActivationCard}
      planContractRefreshCard={planContractRefreshCard}
      snapshotCommissionDefaultCountries={snapshotCommissionDefaultCountries}
      snapshotCommissionDefaultCategories={snapshotCommissionDefaultCategories}
      snapshotCommissionDefaultMaxRowsPerScope={snapshotCommissionDefaultMaxRowsPerScope}
      attentionRows={attentionRows}
      operatorHealth={operatorHealth}
      operatorNextAction={operatorNextAction}
      pipelineMetrics={pipelineMetrics}
      deliverySplit={deliverySplit}
      coverageRows={coverageRows}
      controlEnvironment={controlEnvironment}
      availableControlEnvironments={availableControlEnvironments}
    />
  );
}

async function withConsoleReadDeadline<T>(label: string, read: () => Promise<T>): Promise<T> {
  let timeout: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([
      read(),
      new Promise<never>((_, reject) => {
        timeout = setTimeout(
          () => reject(new Error(`${label} did not respond within ${CONSOLE_READ_DEADLINE_MS / 1000}s.`)),
          CONSOLE_READ_DEADLINE_MS
        );
      })
    ]);
  } finally {
    if (timeout) {
      clearTimeout(timeout);
    }
  }
}

function freshStepUpExpiry(stepUpSatisfiedAt: string | undefined): string | undefined {
  if (!stepUpSatisfiedAt) {
    return undefined;
  }
  const satisfiedMs = Date.parse(stepUpSatisfiedAt);
  if (!Number.isFinite(satisfiedMs)) {
    return undefined;
  }
  return new Date(satisfiedMs + STAGING_CANARY_FRESH_STEP_UP_WINDOW_MS).toISOString();
}
