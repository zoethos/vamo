"use client";

import Link from "next/link";
import { useState } from "react";
import type { AdminAssuranceLevel, AdminPrincipal } from "@confluendo/ingestion-platform/admin-auth";
import type {
  AutonomyDashboardView,
  BatchQueueItem,
  BatchQueueItemStatus,
  BatchQueueSnapshot
} from "@confluendo/ingestion-platform/core";
import type {
  IngestionAction,
  IngestionEvent,
  IngestionInstance,
  IngestionSignal,
  IngestionStat,
  IngestionTarget
} from "@confluendo/ingestion-platform/read-model";
import type { ProgressiveRunView } from "@confluendo/ingestion-platform/progressive-read-model";
import { AdminSessionActions } from "@/app/admin/admin-session-actions";
import { ConfluendoMark } from "@/app/admin/confluendo-brand";
import { DashboardThemeToggle } from "@/app/admin/dashboard-theme-toggle";
import { AgentView } from "./agent-view";
import { BatchQueueScheduleControl } from "./batch-queue-schedule-control";
import { BatchCanaryWaveApprovalControl } from "./batch-canary-wave-approval-control";
import { ProductionPackageWaveApprovalControl } from "./production-package-wave-approval-control";
import { ProductionPackageConsumerApplyControl } from "./production-package-consumer-apply-control";
import { ProductionInboxControl } from "./production-inbox-control";
import { StagingCanaryControl } from "./staging-canary-control";
import {
  ClusterCommandControls,
  RecoveryCommandButton,
  TargetCommandButton
} from "./ingestion-command-controls";
import { IngestionQueueTable } from "./ingestion-queue-table";
import {
  autonomySourceLabel,
  batchQueueSourceLabel,
  buildStatusDistribution,
  consoleViewLabels,
  formatAgentAction,
  friendlyCategory,
  friendlyGeo,
  friendlyUnit,
  percentOf,
  progressiveSourceLabel,
  queueStatusLabels,
  queueStatusTones,
  statusLabels,
  toneLabels,
  type ConsoleView,
  type OperatorTone,
  type StatusSlice
} from "./ingestion-console-labels";

type DashboardSource = "live" | "sample" | "error";

interface OperatorMetric {
  label: string;
  value: string | number;
  detail: string;
  tone: OperatorTone;
}

interface OperatorHealth {
  title: string;
  detail: string;
  tone: OperatorTone;
}

interface ProductionPackageWavePresentation {
  waveKey: string;
  status: string;
  schemaContract: string;
  approvalExpiresAt?: string;
  consumerApplyStatus?: string | null;
  telemetrySource?: string;
  packageId?: string | null;
  statusPresentation: {
    label: string;
    tone: "neutral" | "good" | "watch" | "danger";
    detail?: string;
  };
    items?: Array<{
    unitKey: string;
    runOrder: number;
    status: string;
    packageId?: string | null;
    consumerApplyStatus?: string | null;
    telemetrySource?: string;
    contentEquivalenceLabel?: string;
    contentEquivalenceStatus?: "match" | "drift_blocked" | "unavailable";
    statusPresentation: {
      label: string;
      tone: "neutral" | "good" | "watch" | "danger";
      detail?: string;
    };
  }>;
}

export interface IngestionConsoleShellProps {
  principal: AdminPrincipal;
  freshStepUpExpiresAt?: string;
  serverNowMs: number;
  source: DashboardSource;
  ingestionSignals: IngestionSignal[];
  ingestionActions: IngestionAction[];
  ingestionInstances: IngestionInstance[];
  ingestionTargets: IngestionTarget[];
  ingestionEvents: IngestionEvent[];
  ingestionStats: IngestionStat[];
  ingestionPolicyLocks: string[];
  progressiveView: ProgressiveRunView;
  progressiveSource: DashboardSource;
  batchQueue: BatchQueueSnapshot;
  batchQueueSource: DashboardSource;
  batchQueueError?: string;
  applyTelemetrySource?: string;
  autonomyView: AutonomyDashboardView;
  autonomySource: DashboardSource;
  autonomyError?: string;
  batchCategories: string[];
  batchCountries: string[];
  batchQueueEligibleCount: number;
  batchCanaryWaveEligibleCount: number;
  productionPackageEligibleCount: number;
  latestProductionPackageWave: ProductionPackageWavePresentation | null;
  attentionRows: BatchQueueItem[];
  operatorHealth: OperatorHealth;
  operatorNextAction: string;
  pipelineMetrics: OperatorMetric[];
  deliverySplit: StatusSlice[];
  coverageRows: Array<{
    country: string;
    cells: Array<{ category: string; value: number }>;
  }>;
  canaryTargetId?: string;
  canaryTargetBounds?: { maxUnits: number; maxRows: number };
  canaryTargetShipment?: ProgressiveRunView["rows"][number]["canaryShipment"];
  canaryTargetShipped?: boolean;
  canaryProductionInbox?: ProgressiveRunView["rows"][number]["productionInbox"];
}

export function IngestionConsoleShell(props: IngestionConsoleShellProps) {
  const [activeView, setActiveView] = useState<ConsoleView>("overview");

  const commandContext = {
    role: props.principal.role,
    assuranceLevel: props.principal.assuranceLevel,
    source: props.source === "error" ? ("sample" as const) : props.source
  };
  const batchContext = {
    role: props.principal.role,
    assuranceLevel: props.principal.assuranceLevel,
    source: props.batchQueueSource
  };
  const progressiveContext = {
    role: props.principal.role,
    assuranceLevel: props.principal.assuranceLevel,
    source: props.progressiveSource === "error" ? ("sample" as const) : props.progressiveSource
  };

  const selectedTarget =
    props.ingestionTargets.find((target) => target.status === "blocked") ??
    props.ingestionTargets[0];
  const statusDistribution = buildStatusDistribution(props.batchQueue.items);
  const {
    rows: progressiveRows,
    summary: progressiveSummary,
    nextAction: progressiveNextAction
  } = props.progressiveView;
  const canaryTarget = progressiveRows.find((row) => row.workStatus === "review_required");

  return (
    <main
      className="provider-dashboard admin-console"
      data-theme="dark"
      id="ingestion-dashboard-theme-root"
    >
      <nav className="provider-masthead admin-masthead" aria-label="Admin dashboard">
        <Link className="provider-brand admin-brand" href="/admin/ingestion">
          <ConfluendoMark className="provider-brand-mark" size={34} />
          <span>Confluendo</span>
        </Link>
        <div className="admin-masthead-controls">
          <div className="admin-nav" aria-label="Admin sections">
            <Link className="admin-nav-link" href="/admin/providers">
              Providers
            </Link>
            <Link className="admin-nav-link admin-nav-link-active" href="/admin/ingestion">
              Ingestion
            </Link>
          </div>
          <AdminSessionActions
            principal={props.principal}
            freshStepUpExpiresAt={props.freshStepUpExpiresAt}
            serverNowMs={props.serverNowMs}
          />
          <DashboardThemeToggle
            defaultTheme="dark"
            label="Ingestion dashboard theme"
            rootId="ingestion-dashboard-theme-root"
            storageKey="ingestion-dashboard-theme"
          />
        </div>
      </nav>

      <nav className="admin-ux-tabs" aria-label="Ingestion console views">
        {(Object.keys(consoleViewLabels) as ConsoleView[]).map((view) => (
          <button
            key={view}
            type="button"
            className={activeView === view ? "admin-ux-tab-active" : undefined}
            aria-current={activeView === view ? "page" : undefined}
            onClick={() => setActiveView(view)}
          >
            {consoleViewLabels[view]}
          </button>
        ))}
      </nav>

      {activeView === "overview" ? (
        <OverviewView
          operatorHealth={props.operatorHealth}
          operatorNextAction={props.operatorNextAction}
          source={props.source}
          ingestionActions={props.ingestionActions}
          commandContext={commandContext}
          pipelineMetrics={props.pipelineMetrics}
          batchQueue={props.batchQueue}
          statusDistribution={statusDistribution}
          deliverySplit={props.deliverySplit}
          applyTelemetrySource={props.applyTelemetrySource}
          coverageRows={props.coverageRows}
          batchCategories={props.batchCategories}
          attentionRows={props.attentionRows}
          autonomyView={props.autonomyView}
        />
      ) : null}

      {activeView === "queue" ? (
        <QueueView
          batchQueue={props.batchQueue}
          batchQueueSource={props.batchQueueSource}
          batchQueueError={props.batchQueueError}
          batchQueueEligibleCount={props.batchQueueEligibleCount}
          batchContext={batchContext}
          batchCountries={props.batchCountries}
          batchCategories={props.batchCategories}
        />
      ) : null}

      {activeView === "agent" ? (
        <AgentView
          autonomyView={props.autonomyView}
          autonomySource={props.autonomySource}
          autonomyError={props.autonomyError}
        />
      ) : null}

      {activeView === "staging" ? (
        <StagingView
          batchQueue={props.batchQueue}
          batchQueueSource={props.batchQueueSource}
          batchCanaryWaveEligibleCount={props.batchCanaryWaveEligibleCount}
          batchContext={batchContext}
        />
      ) : null}

      {activeView === "delivery" ? (
        <DeliveryView
          batchQueue={props.batchQueue}
          batchQueueSource={props.batchQueueSource}
          productionPackageEligibleCount={props.productionPackageEligibleCount}
          latestProductionPackageWave={props.latestProductionPackageWave}
          applyTelemetrySource={props.applyTelemetrySource}
          batchContext={batchContext}
        />
      ) : null}

      {activeView === "diagnostics" ? (
        <DiagnosticsView
          principal={props.principal}
          source={props.source}
          ingestionSignals={props.ingestionSignals}
          ingestionInstances={props.ingestionInstances}
          ingestionTargets={props.ingestionTargets}
          ingestionEvents={props.ingestionEvents}
          ingestionStats={props.ingestionStats}
          ingestionPolicyLocks={props.ingestionPolicyLocks}
          commandContext={commandContext}
          selectedTarget={selectedTarget}
          progressiveRows={progressiveRows}
          progressiveSummary={progressiveSummary}
          progressiveNextAction={progressiveNextAction}
          progressiveSource={props.progressiveSource}
          canaryTarget={canaryTarget}
          progressiveContext={progressiveContext}
        />
      ) : null}

      <p className="provider-backlink admin-backlink">
        <Link href="/admin/providers">Back to provider control</Link>
      </p>
    </main>
  );
}

function OverviewView({
  operatorHealth,
  operatorNextAction,
  source,
  ingestionActions,
  commandContext,
  pipelineMetrics,
  batchQueue,
  statusDistribution,
  deliverySplit,
  applyTelemetrySource,
  coverageRows,
  batchCategories,
  attentionRows,
  autonomyView
}: {
  operatorHealth: OperatorHealth;
  operatorNextAction: string;
  source: DashboardSource;
  ingestionActions: IngestionAction[];
  commandContext: { role: AdminPrincipal["role"]; assuranceLevel: AdminPrincipal["assuranceLevel"]; source: "live" | "sample" };
  pipelineMetrics: OperatorMetric[];
  batchQueue: BatchQueueSnapshot;
  statusDistribution: StatusSlice[];
  deliverySplit: StatusSlice[];
  applyTelemetrySource?: string;
  coverageRows: IngestionConsoleShellProps["coverageRows"];
  batchCategories: string[];
  attentionRows: BatchQueueItem[];
  autonomyView: AutonomyDashboardView;
}) {
  return (
    <>
      <section className="admin-ux-overview" aria-label="Ingestion overview">
        <div className={`admin-ux-health admin-ux-tone-${operatorHealth.tone}`}>
          <div>
            <span className="admin-ux-label">Ingestion health</span>
            <h1>{operatorHealth.title}</h1>
            <p>{operatorHealth.detail}</p>
          </div>
          <div className="admin-ux-next-action">
            <span className="admin-ux-label">Next recommended action</span>
            <strong>{operatorNextAction}</strong>
          </div>
        </div>
        <aside className="admin-ux-control-panel" aria-label="Manual overrides">
          <div className="admin-surface-header">
            <span>Manual overrides</span>
            <strong>{source === "live" ? "Live control plane" : "Sample preview"}</strong>
          </div>
          <p className="admin-ux-panel-note">
            Cluster commands bypass the agent schedule. Use only when you need direct worker
            control.
          </p>
          <ClusterCommandControls actions={ingestionActions} context={commandContext} />
        </aside>
      </section>

      <section className="admin-ux-metrics" aria-label="Pipeline status">
        {pipelineMetrics.map((metric) => (
          <article className={`admin-ux-metric admin-ux-tone-${metric.tone}`} key={metric.label}>
            <span>{metric.label}</span>
            <strong>{metric.value}</strong>
            <p>{metric.detail}</p>
          </article>
        ))}
      </section>

      <section className="admin-ux-agent-strip" aria-label="Agent status">
        <div className="admin-ux-panel">
          <div className="admin-ux-panel-heading">
            <div>
              <span className="admin-ux-label">Agent</span>
              <h2>Next agent cycle</h2>
            </div>
            <strong>{formatAgentAction(autonomyView.nextCycle.requiredAction)}</strong>
          </div>
          <p>
            Decision: {autonomyView.nextCycle.decision} · phase {autonomyView.nextCycle.phase}
            {autonomyView.nextCycle.pauseReason
              ? ` · paused: ${autonomyView.nextCycle.pauseReason}`
              : ""}
          </p>
          {autonomyView.policy ? (
            <p>
              Operating policy: {autonomyView.policy.policyKey} · {autonomyView.policy.rampLabel} ·
              max {autonomyView.policy.maxUnitsPerCycle} scopes /{" "}
              {autonomyView.policy.maxRowsPerCycle} rows per cycle
            </p>
          ) : (
            <p>No active operating policy.</p>
          )}
        </div>
      </section>

      <section className="admin-ux-analytics" aria-label="Operational charts">
        <div className="admin-ux-panel">
          <div className="admin-ux-panel-heading">
            <div>
              <span className="admin-ux-label">Queue</span>
              <h2>Lifecycle distribution</h2>
            </div>
            <strong>{batchQueue.progress.total} scopes</strong>
          </div>
          <div className="admin-ux-bars">
            {statusDistribution.map((slice) => (
              <div className="admin-ux-bar-row" key={slice.label}>
                <span>{slice.label}</span>
                <div className="admin-ux-bar-track">
                  <span
                    className={`admin-ux-bar-fill admin-ux-fill-${slice.tone}`}
                    style={{ width: `${slice.percent}%` }}
                  />
                </div>
                <strong>{slice.value}</strong>
              </div>
            ))}
          </div>
        </div>

        <div className="admin-ux-panel">
          <div className="admin-ux-panel-heading">
            <div>
              <span className="admin-ux-label">Consumer inbox</span>
              <h2>Delivery and consumer apply</h2>
            </div>
            <strong>
              {applyTelemetrySource === "inbox" ? "Inbox telemetry" : "Control ledger"}
            </strong>
          </div>
          <div className="admin-ux-stacked-bar" aria-hidden="true">
            {deliverySplit.map((slice) => (
              <span
                className={`admin-ux-fill-${slice.tone}`}
                key={slice.label}
                style={{ width: `${slice.percent}%` }}
              />
            ))}
          </div>
          <div className="admin-ux-split-list">
            {deliverySplit.map((slice) => (
              <div key={slice.label}>
                <span className={`admin-ux-dot admin-ux-fill-${slice.tone}`} />
                <span>{slice.label}</span>
                <strong>{slice.value}</strong>
              </div>
            ))}
          </div>
        </div>

        <div className="admin-ux-panel admin-ux-coverage-panel">
          <div className="admin-ux-panel-heading">
            <div>
              <span className="admin-ux-label">Coverage</span>
              <h2>Country and category matrix</h2>
            </div>
            <strong>{batchQueue.sourceKey}</strong>
          </div>
          <div className="admin-ux-matrix-wrap">
            <table className="admin-ux-matrix">
              <thead>
                <tr>
                  <th>Country</th>
                  {batchCategories.map((category) => (
                    <th key={category}>{friendlyCategory(category)}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {coverageRows.map((row) => (
                  <tr key={row.country}>
                    <th>{friendlyGeo(row.country)}</th>
                    {row.cells.map((cell) => (
                      <td key={`${row.country}-${cell.category}`} data-empty={cell.value === 0}>
                        {cell.value || "·"}
                      </td>
                    ))}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>

        <div className="admin-ux-panel">
          <div className="admin-ux-panel-heading">
            <div>
              <span className="admin-ux-label">Exceptions</span>
              <h2>Human action required</h2>
            </div>
            <strong>{attentionRows.length}</strong>
          </div>
          {attentionRows.length > 0 ? (
            <ol className="admin-ux-attention-list">
              {attentionRows.map((item) => (
                <li key={item.unitKey}>
                  <strong>{friendlyUnit(item.unitKey)}</strong>
                  <span>{queueStatusLabels[item.status]}</span>
                  <p>{item.blockReasons[0] ?? "Review the latest ledger evidence."}</p>
                </li>
              ))}
            </ol>
          ) : (
            <p className="admin-ux-empty">No operator action is currently required.</p>
          )}
        </div>
      </section>
    </>
  );
}

function QueueView({
  batchQueue,
  batchQueueSource,
  batchQueueError,
  batchQueueEligibleCount,
  batchContext,
  batchCountries,
  batchCategories
}: {
  batchQueue: BatchQueueSnapshot;
  batchQueueSource: DashboardSource;
  batchQueueError?: string;
  batchQueueEligibleCount: number;
  batchContext: { role: AdminPrincipal["role"]; assuranceLevel: AdminPrincipal["assuranceLevel"]; source: DashboardSource };
  batchCountries: string[];
  batchCategories: string[];
}) {
  return (
    <section className="admin-ux-section admin-ux-view-panel" aria-label="Batch queue">
      <div className="admin-section-heading admin-section-heading-compact">
        <div>
          <p className="admin-kicker">Batch queue</p>
          <h2>Scopes moving through the pipeline</h2>
          <p className="admin-view-lead">
            Filter and group loaded scopes. Simulation, staging, and delivery controls live in
            their dedicated views.
          </p>
        </div>
        <span className="admin-readonly-pill">{batchQueueSourceLabel(batchQueueSource)}</span>
      </div>
      {batchQueueError ? (
        <p className="admin-command-result admin-command-result-error" role="alert">
          {batchQueueError}
        </p>
      ) : null}
      <p className="admin-next-action">
        <strong>Next action:</strong> {batchQueue.nextAction}
      </p>
      <BatchQueueScheduleControl
        projectKey={batchQueue.projectKey}
        targetKey={batchQueue.targetKey}
        eligibleCount={batchQueueEligibleCount}
        context={batchContext}
      />
      <div className="admin-queue-stats">
        <span>
          {batchQueue.progress.total} scopes · {batchQueue.progress.ready} ready to simulate
        </span>
        <span>
          {batchQueue.progress.stagingCanary.succeeded} staging verified ·{" "}
          {batchQueue.progress.productionPackage.delivered} delivered to inbox
        </span>
      </div>
      {batchQueue.blockerSummaries.length > 0 ? (
        <div className="admin-table-wrap admin-queue-blockers">
          <table className="admin-target-table">
            <thead>
              <tr>
                <th>Exception</th>
                <th>Scopes</th>
              </tr>
            </thead>
            <tbody>
              {batchQueue.blockerSummaries.map((blocker) => (
                <tr key={blocker.reason}>
                  <td>
                    <code>{blocker.reason}</code>
                  </td>
                  <td>{blocker.count}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : null}
      <IngestionQueueTable items={batchQueue.items} sourceKey={batchQueue.sourceKey} />
      <details className="admin-evidence-details">
        <summary>Coverage matrix (raw)</summary>
        <div className="admin-table-wrap">
          <table className="admin-target-table">
            <thead>
              <tr>
                <th>Country \ Category</th>
                {batchCategories.map((category) => (
                  <th key={category}>{category}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {batchCountries.map((country) => (
                <tr key={country}>
                  <td>
                    <strong>{country}</strong>
                  </td>
                  {batchCategories.map((category) => (
                    <td key={`${country}-${category}`}>
                      {batchQueue.coverage.matrix[country]?.[category] ?? 0}
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </details>
    </section>
  );
}

function StagingView({
  batchQueue,
  batchQueueSource,
  batchCanaryWaveEligibleCount,
  batchContext
}: {
  batchQueue: BatchQueueSnapshot;
  batchQueueSource: DashboardSource;
  batchCanaryWaveEligibleCount: number;
  batchContext: { role: AdminPrincipal["role"]; assuranceLevel: AdminPrincipal["assuranceLevel"]; source: DashboardSource };
}) {
  return (
    <section className="admin-ux-section admin-ux-view-panel" aria-label="Staging verification">
      <div className="admin-section-heading admin-section-heading-compact">
        <div>
          <p className="admin-kicker">Staging verification</p>
          <h2>Verify candidate writes in staging</h2>
          <p className="admin-view-lead">
            Staging verification exercises consumer-shaped writes against the staging target.
            Production and the consumer inbox are not touched here. Failed or blocked scopes need
            investigation before retry — do not widen volume until evidence is clean.
          </p>
        </div>
        <span className="admin-readonly-pill">{batchQueueSourceLabel(batchQueueSource)}</span>
      </div>
      <BatchCanaryWaveApprovalControl
        projectKey={batchQueue.projectKey}
        targetKey={batchQueue.targetKey}
        targetEnvironment={batchQueue.targetEnvironment}
        eligibleCount={batchCanaryWaveEligibleCount}
        queueItems={batchQueue.items}
        latestWave={batchQueue.latestWave}
        context={batchContext}
      />
      {batchQueue.latestWave ? (
        <>
          <p className="admin-next-action">
            <strong>Latest staging batch:</strong> {batchQueue.latestWave.waveKey} ·{" "}
            {batchQueue.latestWave.status} · {batchQueue.latestWave.targetEnvironment} ·{" "}
            {batchQueue.latestWave.unitCount} scope(s)
            {batchQueue.latestWave.approvalAuditId
              ? ` · audit record ${batchQueue.latestWave.approvalAuditId}`
              : ""}
            {batchQueue.latestWave.executionAuditId
              ? ` · execution audit ${batchQueue.latestWave.executionAuditId}`
              : ""}
            {batchQueue.latestWave.approvalExpiresAt
              ? ` · expires ${batchQueue.latestWave.approvalExpiresAt}`
              : ""}
          </p>
          {batchQueue.latestWave.items && batchQueue.latestWave.items.length > 0 ? (
            <div className="admin-table-wrap">
              <table className="admin-target-table">
                <thead>
                  <tr>
                    <th>#</th>
                    <th>Scope</th>
                    <th>Status</th>
                    <th>Expected target writes</th>
                    <th>Shipment</th>
                    <th>Exceptions</th>
                  </tr>
                </thead>
                <tbody>
                  {batchQueue.latestWave.items.map((item) => (
                    <tr key={item.unitKey}>
                      <td>{item.runOrder}</td>
                      <td>
                        <strong>{friendlyUnit(item.unitKey)}</strong>
                        <code className="admin-evidence-code">{item.unitKey}</code>
                      </td>
                      <td>
                        {queueStatusLabels[item.status as BatchQueueItemStatus] ?? item.status}
                      </td>
                      <td>{item.plannedRowCount}</td>
                      <td>{item.shipmentId ?? "—"}</td>
                      <td>{item.blockers.length > 0 ? item.blockers.join(", ") : "—"}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ) : null}
        </>
      ) : (
        <p className="admin-ux-empty">No staging batches recorded yet.</p>
      )}
      <div className="admin-stat-grid">
        <article className="admin-stat">
          <span>Eligible</span>
          <strong>{batchQueue.progress.stagingCanary.dryRunSucceededEligible}</strong>
          <p>Simulation-passed scopes ready for staging</p>
        </article>
        <article className="admin-stat">
          <span>Verified</span>
          <strong>{batchQueue.progress.stagingCanary.succeeded}</strong>
          <p>Staging verification succeeded</p>
        </article>
        <article className="admin-stat">
          <span>Blocked</span>
          <strong>{batchQueue.progress.stagingCanary.blocked}</strong>
          <p>Require investigation</p>
        </article>
      </div>
    </section>
  );
}

function DeliveryView({
  batchQueue,
  batchQueueSource,
  productionPackageEligibleCount,
  latestProductionPackageWave,
  applyTelemetrySource,
  batchContext
}: {
  batchQueue: BatchQueueSnapshot;
  batchQueueSource: DashboardSource;
  productionPackageEligibleCount: number;
  latestProductionPackageWave: ProductionPackageWavePresentation | null;
  applyTelemetrySource?: string;
  batchContext: { role: AdminPrincipal["role"]; assuranceLevel: AdminPrincipal["assuranceLevel"]; source: DashboardSource };
}) {
  return (
    <section className="admin-ux-section admin-ux-view-panel" aria-label="Consumer inbox delivery">
      <div className="admin-section-heading admin-section-heading-compact">
        <div>
          <p className="admin-kicker">Consumer inbox delivery</p>
          <h2>Deliver verified packages to the consumer inbox</h2>
          <p className="admin-view-lead">
            Delivery packages land in the consumer inbox only.{" "}
            <strong>Delivered to consumer inbox</strong> is separate from{" "}
            <strong>Applied by consumer</strong> — product-table apply remains consumer-owned.
          </p>
        </div>
        <span className="admin-readonly-pill">{batchQueueSourceLabel(batchQueueSource)}</span>
      </div>
      <ProductionPackageWaveApprovalControl
        projectKey={batchQueue.projectKey}
        targetKey={batchQueue.targetKey}
        eligibleCount={productionPackageEligibleCount}
        packageProgress={batchQueue.progress.productionPackage}
        latestWave={latestProductionPackageWave}
        context={batchContext}
      />
      {batchQueue.latestProductionPackageWave ? (
        <>
          <p className="admin-next-action">
            <strong>Latest delivery batch:</strong> {batchQueue.latestProductionPackageWave.waveKey}{" "}
            ·{" "}
            {latestProductionPackageWave?.statusPresentation.label ??
              batchQueue.latestProductionPackageWave.status}{" "}
            · {batchQueue.latestProductionPackageWave.targetEnvironment} ·{" "}
            {batchQueue.latestProductionPackageWave.unitCount} scope(s)
            {batchQueue.latestProductionPackageWave.approvalAuditId
              ? ` · approval audit record ${batchQueue.latestProductionPackageWave.approvalAuditId}`
              : ""}
            {batchQueue.latestProductionPackageWave.deliveryAuditId
              ? ` · delivery audit record ${batchQueue.latestProductionPackageWave.deliveryAuditId}`
              : ""}
            {applyTelemetrySource === "inbox"
              ? " · apply telemetry from inbox"
              : batchQueue.latestProductionPackageWave.status === "delivered" ||
                  batchQueue.latestProductionPackageWave.status === "consumer_apply_pending" ||
                  batchQueue.latestProductionPackageWave.status === "consumer_applied" ||
                  batchQueue.latestProductionPackageWave.status === "consumer_apply_failed"
                ? " · apply telemetry unavailable"
                : ""}
          </p>
          {latestProductionPackageWave?.items && latestProductionPackageWave.items.length > 0 ? (
            <div className="admin-table-wrap">
              <table className="admin-target-table">
                <thead>
                  <tr>
                    <th>#</th>
                    <th>Scope</th>
                    <th>Inbox delivery</th>
                    <th>Consumer apply</th>
                      <th>Content</th>
                      <th>Package id</th>
                  </tr>
                </thead>
                <tbody>
                  {latestProductionPackageWave.items.map((item) => (
                    <tr key={item.unitKey}>
                      <td>{item.runOrder}</td>
                      <td>
                        <strong>{friendlyUnit(item.unitKey)}</strong>
                        <code className="admin-evidence-code">{item.unitKey}</code>
                      </td>
                      <td>{item.status}</td>
                        <td>
                          {item.statusPresentation.label}
                          {item.telemetrySource === "missing" &&
                          (item.status === "delivered" ||
                            item.status === "production_package_delivered" ||
                            item.status === "consumer_apply_pending")
                            ? " (telemetry missing)"
                            : ""}
                        </td>
                        <td>{item.contentEquivalenceLabel ?? "Hash unavailable"}</td>
                        <td>
                        <code>{item.packageId ?? "—"}</code>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ) : null}
          {latestProductionPackageWave?.items
            ?.filter((item) => isConsumerApplyEligible(item))
            .map((item) => (
              <ProductionPackageConsumerApplyControl
                key={`apply-${item.unitKey}`}
                projectKey={batchQueue.projectKey}
                packageId={item.packageId ?? ""}
                unitKey={item.unitKey}
                shipmentStatus={
                  item.consumerApplyStatus === "pending" ? "production_inbox_delivered" : item.status
                }
                pendingItemCount={item.consumerApplyStatus === "pending" ? 1 : undefined}
                context={batchContext}
              />
            ))}
        </>
      ) : (
        <p className="admin-ux-empty">No delivery batches recorded yet.</p>
      )}
      <div className="admin-stat-grid">
        <article className="admin-stat">
          <span>Eligible</span>
          <strong>{productionPackageEligibleCount}</strong>
          <p>Staging-verified scopes ready for delivery</p>
        </article>
        <article className="admin-stat">
          <span>Delivered to inbox</span>
          <strong>{batchQueue.progress.productionPackage.delivered}</strong>
          <p>Awaiting or past consumer apply</p>
        </article>
        <article className="admin-stat">
          <span>Applied by consumer</span>
          <strong>{batchQueue.progress.productionPackage.applied}</strong>
          <p>Consumer confirmed product apply</p>
        </article>
        <article className="admin-stat">
          <span>Apply failed</span>
          <strong>{batchQueue.progress.productionPackage.applyFailed}</strong>
          <p>Needs consumer investigation</p>
        </article>
      </div>
    </section>
  );
}

function isConsumerApplyEligible(item: {
  packageId?: string | null;
  status: string;
  consumerApplyStatus?: string | null;
}): boolean {
  if (!item.packageId) {
    return false;
  }
  if (item.consumerApplyStatus === "applied" || item.consumerApplyStatus === "failed") {
    return false;
  }
  return (
    item.consumerApplyStatus === "pending" ||
    item.status === "delivered" ||
    item.status === "production_package_delivered" ||
    item.status === "consumer_apply_pending"
  );
}

function DiagnosticsView({
  principal,
  source,
  ingestionSignals,
  ingestionInstances,
  ingestionTargets,
  ingestionEvents,
  ingestionStats,
  ingestionPolicyLocks,
  commandContext,
  selectedTarget,
  progressiveRows,
  progressiveSummary,
  progressiveNextAction,
  progressiveSource,
  canaryTarget,
  progressiveContext
}: {
  principal: AdminPrincipal;
  source: DashboardSource;
  ingestionSignals: IngestionSignal[];
  ingestionInstances: IngestionInstance[];
  ingestionTargets: IngestionTarget[];
  ingestionEvents: IngestionEvent[];
  ingestionStats: IngestionStat[];
  ingestionPolicyLocks: string[];
  commandContext: { role: AdminPrincipal["role"]; assuranceLevel: AdminPrincipal["assuranceLevel"]; source: "live" | "sample" };
  selectedTarget?: IngestionTarget;
  progressiveRows: ProgressiveRunView["rows"];
  progressiveSummary: ProgressiveRunView["summary"];
  progressiveNextAction: string;
  progressiveSource: DashboardSource;
  canaryTarget?: ProgressiveRunView["rows"][number];
  progressiveContext: { role: AdminPrincipal["role"]; assuranceLevel: AdminPrincipal["assuranceLevel"]; source: "live" | "sample" };
}) {
  return (
    <>
      <section className="admin-ux-section admin-ux-view-panel" aria-label="Diagnostics">
        <div className="admin-section-heading admin-section-heading-compact">
          <div>
            <p className="admin-kicker">Diagnostics</p>
            <h2>Raw evidence and legacy rollout panels</h2>
            <p className="admin-view-lead">
              Internal rollout telemetry, target boards, and IP-specific read models. Use for
              traceability — not the primary operator workflow.
            </p>
          </div>
          <span className="admin-readonly-pill">
            {principal.role} · {principal.assuranceLevel}
          </span>
        </div>
      </section>

      <section className="admin-signal-grid admin-legacy-section" aria-label="Ingestion summary">
        {ingestionSignals.map((signal) => (
          <article className={`admin-signal admin-tone-${signal.tone}`} key={signal.label}>
            <span>{signal.label}</span>
            <strong>{signal.value}</strong>
            <p>{signal.detail}</p>
          </article>
        ))}
      </section>

      <section className="admin-section admin-legacy-section">
        <div className="admin-section-heading">
          <div>
            <p className="admin-kicker">Workers</p>
            <h2>Containerized workers</h2>
          </div>
          <span className="admin-readonly-pill">
            {source === "live" ? "Live control plane" : "Sample preview"}
          </span>
        </div>
        <div className="admin-instance-grid">
          {ingestionInstances.map((instance) => (
            <article className="admin-instance-card" key={instance.id}>
              <div className="admin-card-topline">
                <div>
                  <h3>{instance.id}</h3>
                  <p>{instance.role}</p>
                </div>
                <span className={`admin-status admin-status-${instance.status}`}>
                  {statusLabels[instance.status]}
                </span>
              </div>
              <dl className="admin-definition-grid">
                <div>
                  <dt>Target</dt>
                  <dd>{instance.currentTarget}</dd>
                </div>
                <div>
                  <dt>Heartbeat</dt>
                  <dd>{instance.heartbeat}</dd>
                </div>
                <div>
                  <dt>Cursor</dt>
                  <dd>{instance.cursor}</dd>
                </div>
                <div>
                  <dt>Throughput</dt>
                  <dd>{instance.throughput}</dd>
                </div>
                <div className="admin-definition-wide">
                  <dt>Network stance</dt>
                  <dd>{instance.network}</dd>
                </div>
              </dl>
            </article>
          ))}
        </div>
      </section>

      <section className="admin-section admin-target-layout admin-legacy-section">
        <div className="admin-target-table-panel">
          <div className="admin-section-heading admin-section-heading-compact">
            <div>
              <p className="admin-kicker">Targets</p>
              <h2>Target board (legacy)</h2>
            </div>
            <span className="admin-table-count">{ingestionTargets.length} targets</span>
          </div>
          <div className="admin-table-wrap">
            <table className="admin-target-table">
              <thead>
                <tr>
                  <th>Target</th>
                  <th>Source</th>
                  <th>Instance</th>
                  <th>Status</th>
                  <th>Checkpoint</th>
                  <th>Signal</th>
                  <th>Control</th>
                </tr>
              </thead>
              <tbody>
                {ingestionTargets.map((target) => (
                  <tr key={target.name}>
                    <td>
                      <strong>{target.name}</strong>
                      <span>{target.scope}</span>
                    </td>
                    <td>{target.source}</td>
                    <td>{target.instance}</td>
                    <td>
                      <span className={`admin-status admin-status-${target.status}`}>
                        {statusLabels[target.status]}
                      </span>
                    </td>
                    <td>
                      <code>{target.checkpoint}</code>
                      <span>{target.throughput}</span>
                    </td>
                    <td>{target.lastSignal}</td>
                    <td>
                      <TargetCommandButton context={commandContext} target={target} />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
        {selectedTarget ? (
          <aside className="admin-failure-panel" aria-label="Failure recovery detail">
            <p className="admin-kicker">Failure telemetry</p>
            <h2>{selectedTarget.name}</h2>
            <span className={`admin-status admin-status-${selectedTarget.status}`}>
              {statusLabels[selectedTarget.status]}
            </span>
            <dl className="admin-definition-grid admin-definition-stack">
              <div>
                <dt>Signal</dt>
                <dd>{selectedTarget.lastSignal}</dd>
              </div>
              <div>
                <dt>Restart point</dt>
                <dd>
                  <code>{selectedTarget.checkpoint}</code>
                </dd>
              </div>
              <div>
                <dt>Recovery rule</dt>
                <dd>
                  Resume only after the policy guard confirms the payload can be stored or the
                  target is marked live-only.
                </dd>
              </div>
            </dl>
            <RecoveryCommandButton context={commandContext} target={selectedTarget} />
          </aside>
        ) : (
          <aside className="admin-failure-panel" aria-label="Failure recovery detail">
            <p className="admin-kicker">Failure telemetry</p>
            <h2>No targets yet</h2>
            <p>This project has no ingestion targets in the control plane yet.</p>
          </aside>
        )}
      </section>

      <section className="admin-section admin-two-column admin-legacy-section">
        <div className="admin-panel">
          <div className="admin-section-heading admin-section-heading-compact">
            <div>
              <p className="admin-kicker">Cache</p>
              <h2>Cache posture</h2>
            </div>
          </div>
          <div className="admin-stat-grid">
            {ingestionStats.map((stat) => (
              <article className="admin-stat" key={stat.label}>
                <span>{stat.label}</span>
                <strong>{stat.value}</strong>
                <p>{stat.detail}</p>
              </article>
            ))}
          </div>
        </div>
        <div className="admin-panel">
          <div className="admin-section-heading admin-section-heading-compact">
            <div>
              <p className="admin-kicker">Events</p>
              <h2>Recent events</h2>
            </div>
          </div>
          <ol className="admin-event-list">
            {ingestionEvents.map((event, index) => (
              <li
                className={`admin-event admin-tone-${event.tone}`}
                key={`${event.time}-${event.signal}-${event.target}-${index}`}
              >
                <time>{event.time}</time>
                <div>
                  <div className="admin-event-title">
                    <strong>{event.signal}</strong>
                    <span>{toneLabels[event.tone]}</span>
                  </div>
                  <p>{event.target}</p>
                  <small>{event.detail}</small>
                </div>
              </li>
            ))}
          </ol>
        </div>
      </section>

      <section className="admin-section admin-legacy-section" aria-label="IP-14 progressive dry run">
        <div className="admin-section-heading admin-section-heading-compact">
          <div>
            <p className="admin-kicker">IP-14 · progressive simulation</p>
            <h2>Target backlog and simulation review</h2>
          </div>
          <span className="admin-table-count">
            {progressiveSourceLabel(progressiveSource)} · {progressiveSummary.reviewRequired}{" "}
            review · {progressiveSummary.blocked} blocked
          </span>
        </div>
        {progressiveSource === "error" ? (
          <p className="admin-command-result admin-command-result-error" role="alert">
            Live progressive read failed; showing bundled sample data and disabling approvals.
          </p>
        ) : null}
        <p className="admin-next-action">
          <strong>Next action:</strong> {progressiveNextAction}
        </p>
        <div className="admin-table-wrap">
          <table className="admin-target-table">
            <thead>
              <tr>
                <th>Target</th>
                <th>Environment</th>
                <th>Work</th>
                <th>Tier / safety</th>
                <th>Score</th>
                <th>Stage</th>
                <th>Checkpoint</th>
                <th>Progress</th>
                <th>Exceptions</th>
                <th>Next approval</th>
              </tr>
            </thead>
            <tbody>
              {progressiveRows.map((row) => (
                <tr key={row.targetId} className={`admin-tone-${row.tone}`}>
                  <td>
                    <strong>{row.targetId}</strong>
                    <span>
                      {row.projectKey} · {row.sourceId}
                    </span>
                  </td>
                  <td>
                    {row.targetEnvironment ? (
                      <span className="admin-readonly-pill">{row.targetEnvironment}</span>
                    ) : (
                      "—"
                    )}
                  </td>
                  <td>{row.workStatus.replace(/_/g, " ")}</td>
                  <td>
                    <code>{row.tier}</code>
                    <span>{row.safetyMode}</span>
                  </td>
                  <td>
                    {row.score}
                    <span>{row.eligible ? "eligible" : "blocked"}</span>
                  </td>
                  <td>{row.stage.replace(/_/g, " ")}</td>
                  <td>
                    <code>{row.checkpoint}</code>
                    <span>{row.shipmentDiff}</span>
                  </td>
                  <td>
                    {row.rowsStaged}/{row.rowsRead} staged
                    <span>
                      {row.policyBlockCount} policy · {row.deadLetterCount} dead-letter
                    </span>
                  </td>
                  <td>{row.blockers.length > 0 ? row.blockers.join(", ") : "—"}</td>
                  <td>{row.nextApproval}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        {progressiveRows[0] ? (
          <div className="admin-rationale">
            <p>
              <strong>Rationale:</strong> {progressiveRows[0].rationale}
            </p>
            <p>
              <strong>AI (advisory, {progressiveRows[0].aiConfidence}):</strong>{" "}
              {progressiveRows[0].aiSummary}
            </p>
          </div>
        ) : null}
        {canaryTarget ? (
          <div className="admin-canary-stack">
            <StagingCanaryControl
              targetId={canaryTarget.targetId}
              bounds={canaryTarget.canaryBounds}
              shipment={canaryTarget.canaryShipment}
              alreadyShipped={canaryTarget.canaryShipped}
              context={progressiveContext}
            />
            <ProductionInboxControl
              targetId={canaryTarget.targetId}
              bounds={canaryTarget.canaryBounds}
              canaryShipment={canaryTarget.canaryShipment}
              productionInbox={canaryTarget.productionInbox}
              context={progressiveContext}
            />
          </div>
        ) : null}
      </section>

      <section className="admin-section admin-policy-panel admin-legacy-section">
        <div>
          <p className="admin-kicker">Policy locks</p>
          <h2>Efficient without poisoning the cache</h2>
        </div>
        <ul>
          {ingestionPolicyLocks.map((policy) => (
            <li key={policy}>{policy}</li>
          ))}
        </ul>
      </section>
    </>
  );
}

// percentOf is used by the server page when building delivery split metrics.
