import type { Metadata } from "next";
import Link from "next/link";
import {
  STAGING_CANARY_FRESH_STEP_UP_WINDOW_MS,
} from "@confluendo/ingestion-platform/core";
import { loadIp18BatchQueue } from "@/lib/ip18-batch-queue-data";
import { loadIp187Autonomy } from "@/lib/ip18-autonomy-data";
import { AdminSessionActions } from "@/app/admin/admin-session-actions";
import { ConfluendoMark } from "@/app/admin/confluendo-brand";
import { DashboardThemeToggle } from "@/app/admin/dashboard-theme-toggle";
import type {
  IngestionStatus,
  IngestionTone,
} from "@/content/ingestion-dashboard";
import { requireIngestionDashboardAccess } from "@/lib/ingestion-admin-auth";
import { loadIngestionDashboard } from "@/lib/ingestion-dashboard-data";
import { loadIp14ProgressiveBoard } from "@/lib/ip14-progressive-data";
import {
  ClusterCommandControls,
  RecoveryCommandButton,
  TargetCommandButton,
} from "./ingestion-command-controls";
import { BatchQueueScheduleControl } from "./batch-queue-schedule-control";
import { BatchCanaryWaveApprovalControl } from "./batch-canary-wave-approval-control";
import { ProductionInboxControl } from "./production-inbox-control";
import { StagingCanaryControl } from "./staging-canary-control";

export const metadata: Metadata = {
  title: "Ingestion control · Confluendo",
  robots: {
    index: false,
    follow: false,
  },
};

export const dynamic = "force-dynamic";

const statusLabels: Record<IngestionStatus, string> = {
  running: "Running",
  paused: "Paused",
  stopped: "Stopped",
  blocked: "Blocked",
  queued: "Queued",
  complete: "Complete",
};

const toneLabels: Record<IngestionTone, string> = {
  good: "Healthy",
  watch: "Watch",
  danger: "Needs action",
  neutral: "Info",
};

export default async function IngestionDashboardPage() {
  const principal = await requireIngestionDashboardAccess({
    projectKey: "vamo",
    nextPath: "/admin/ingestion",
  });
  const serverNowMs = Date.now();
  const freshStepUpExpiresAt = freshStepUpExpiry(principal.stepUpSatisfiedAt);

  const { view, source } = await loadIngestionDashboard("vamo");
  const { view: progressiveView, source: progressiveSource } =
    await loadIp14ProgressiveBoard("vamo");
  const {
    rows: progressiveRows,
    summary: progressiveSummary,
    nextAction: progressiveNextAction,
  } = progressiveView;
  const {
    signals: ingestionSignals,
    actions: ingestionActions,
    instances: ingestionInstances,
    targets: ingestionTargets,
    events: ingestionEvents,
    stats: ingestionStats,
    policyLocks: ingestionPolicyLocks,
  } = view;
  const selectedTarget =
    ingestionTargets.find((target) => target.status === "blocked") ??
    ingestionTargets[0];
  const canaryTarget = progressiveRows.find(
    (row) => row.workStatus === "review_required",
  );
  const commandContext = {
    role: principal.role,
    assuranceLevel: principal.assuranceLevel,
    source,
  };
  const {
    snapshot: batchQueue,
    source: batchQueueSource,
    error: batchQueueError
  } = await loadIp18BatchQueue("vamo");
  const {
    view: autonomyView,
    source: autonomySource,
    error: autonomyError
  } = await loadIp187Autonomy("vamo");
  const batchCategories = Object.keys(batchQueue.coverage.perCategory).sort();
  const batchCountries = Object.keys(batchQueue.coverage.perCountry).sort();
  const batchQueueEligibleCount = batchQueue.items.filter(
    (item) => item.status === "ready_for_dry_run"
  ).length;
  const batchCanaryWaveEligibleCount = batchQueue.progress.stagingCanary.dryRunSucceededEligible;

  return (
    <main
      className="provider-dashboard admin-console"
      data-theme="light"
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
            <Link
              className="admin-nav-link admin-nav-link-active"
              href="/admin/ingestion"
            >
              Ingestion
            </Link>
          </div>
          <AdminSessionActions
            principal={principal}
            freshStepUpExpiresAt={freshStepUpExpiresAt}
            serverNowMs={serverNowMs}
          />
          <DashboardThemeToggle
            defaultTheme="light"
            label="Ingestion dashboard theme"
            rootId="ingestion-dashboard-theme-root"
            storageKey="ingestion-dashboard-theme"
          />
        </div>
      </nav>

      <section className="admin-hero">
        <div className="admin-hero-copy">
          <p className="admin-kicker">Vamo project · place intelligence</p>
          <h1>Ingestion control</h1>
          <p>
            Visual shell for managing cache loaders, enrichment workers, target
            checkpoints, and promotion telemetry with session-authenticated
            operator controls.
          </p>
        </div>
        <div className="admin-command-surface" aria-label="Global ingestion controls">
          <div className="admin-surface-header">
            <span>Cluster controls</span>
            <strong>{source === "live" ? "Live control plane" : "Sample preview"}</strong>
          </div>
          <ClusterCommandControls
            actions={ingestionActions}
            context={commandContext}
          />
        </div>
      </section>

      <section className="admin-signal-grid" aria-label="Ingestion summary">
        {ingestionSignals.map((signal) => (
          <article
            className={`admin-signal admin-tone-${signal.tone}`}
            key={signal.label}
          >
            <span>{signal.label}</span>
            <strong>{signal.value}</strong>
            <p>{signal.detail}</p>
          </article>
        ))}
      </section>

      <section className="admin-section">
        <div className="admin-section-heading">
          <div>
            <p className="admin-kicker">Instances</p>
            <h2>Containerized workers</h2>
          </div>
          <span className="admin-readonly-pill">
            {principal.role} · {principal.assuranceLevel}
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

      <section className="admin-section admin-target-layout">
        <div className="admin-target-table-panel">
          <div className="admin-section-heading admin-section-heading-compact">
            <div>
              <p className="admin-kicker">Targets</p>
              <h2>One board for every source</h2>
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
                      <TargetCommandButton
                        context={commandContext}
                        target={target}
                      />
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
                Resume only after the policy guard confirms the payload can be
                stored or the target is marked live-only.
              </dd>
            </div>
          </dl>
          <RecoveryCommandButton
            context={commandContext}
            target={selectedTarget}
          />
        </aside>
        ) : (
          <aside className="admin-failure-panel" aria-label="Failure recovery detail">
            <p className="admin-kicker">Failure telemetry</p>
            <h2>No targets yet</h2>
            <p>This project has no ingestion targets in the control plane yet.</p>
          </aside>
        )}
      </section>

      <section className="admin-section admin-two-column">
        <div className="admin-panel">
          <div className="admin-section-heading admin-section-heading-compact">
            <div>
              <p className="admin-kicker">Stats</p>
              <h2>Current cache posture</h2>
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
              <p className="admin-kicker">Signals</p>
              <h2>Recent events</h2>
            </div>
          </div>
          <ol className="admin-event-list">
            {ingestionEvents.map((event) => (
              <li className={`admin-event admin-tone-${event.tone}`} key={`${event.time}-${event.signal}`}>
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

      <section className="admin-section" aria-label="IP-14 progressive dry run">
        <div className="admin-section-heading admin-section-heading-compact">
          <div>
            <p className="admin-kicker">IP-14 · progressive dry run</p>
            <h2>Target backlog and dry-run review</h2>
          </div>
          <span className="admin-table-count">
            {progressiveSourceLabel(progressiveSource)} ·{" "}
            {progressiveSummary.reviewRequired} review · {progressiveSummary.blocked} blocked
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
                <th>Blocks</th>
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
                  <td>
                    {row.blockers.length > 0 ? row.blockers.join(", ") : "—"}
                  </td>
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
              context={{
                role: principal.role,
                assuranceLevel: principal.assuranceLevel,
                source: progressiveSource,
              }}
            />
            <ProductionInboxControl
              targetId={canaryTarget.targetId}
              bounds={canaryTarget.canaryBounds}
              canaryShipment={canaryTarget.canaryShipment}
              productionInbox={canaryTarget.productionInbox}
              context={{
                role: principal.role,
                assuranceLevel: principal.assuranceLevel,
                source: progressiveSource,
              }}
            />
          </div>
        ) : null}
      </section>

      <section className="admin-section" aria-label="IP-18 batch queue">
        <div className="admin-section-heading admin-section-heading-compact">
          <div>
            <p className="admin-kicker">IP-18.5 · batch queue</p>
            <h2>Automated target batch queue</h2>
          </div>
          <span className="admin-readonly-pill">
            {batchQueueSourceLabel(batchQueueSource)}
          </span>
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
          context={{
            role: principal.role,
            assuranceLevel: principal.assuranceLevel,
            source: batchQueueSource
          }}
        />
        <BatchCanaryWaveApprovalControl
          projectKey={batchQueue.projectKey}
          targetKey={batchQueue.targetKey}
          targetEnvironment={batchQueue.targetEnvironment}
          eligibleCount={batchCanaryWaveEligibleCount}
          context={{
            role: principal.role,
            assuranceLevel: principal.assuranceLevel,
            source: batchQueueSource
          }}
        />
        <div className="admin-stat-grid">
          <article className="admin-stat">
            <span>Queue</span>
            <strong>{batchQueue.queueId}</strong>
            <p>
              {batchQueue.targetKey} · {batchQueue.targetEnvironment}
            </p>
          </article>
          <article className="admin-stat">
            <span>Progress</span>
            <strong>{batchQueue.progress.total}</strong>
            <p>
              {batchQueue.progress.ready} ready · {batchQueue.progress.planned} planned ·{" "}
              {batchQueue.progress.blocked} blocked
            </p>
          </article>
          <article className="admin-stat">
            <span>Execution</span>
            <strong>{batchQueue.progress.execution.dryRunSucceeded}</strong>
            <p>
              {batchQueue.progress.execution.dryRunReady} ready ·{" "}
              {batchQueue.progress.execution.dryRunRunning} running ·{" "}
              {batchQueue.progress.execution.dryRunBlocked} blocked
            </p>
          </article>
          <article className="admin-stat">
            <span>Staging canary</span>
            <strong>{batchQueue.progress.stagingCanary.approved}</strong>
            <p>
              {batchQueue.progress.stagingCanary.dryRunSucceededEligible} eligible ·{" "}
              {batchQueue.progress.stagingCanary.succeeded} succeeded ·{" "}
              {batchQueue.progress.stagingCanary.blocked} blocked
            </p>
          </article>
          <article className="admin-stat">
            <span>Applied</span>
            <strong>{batchQueue.progress.applied}</strong>
            <p>{batchQueue.sourceKey}</p>
          </article>
        </div>

        {batchQueue.latestWave ? (
          <>
            <p className="admin-next-action">
              <strong>Latest wave:</strong> {batchQueue.latestWave.waveKey} ·{" "}
              {batchQueue.latestWave.status} · {batchQueue.latestWave.targetEnvironment} ·{" "}
              {batchQueue.latestWave.unitCount} unit(s)
              {batchQueue.latestWave.approvalAuditId
                ? ` · approval audit ${batchQueue.latestWave.approvalAuditId}`
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
                      <th>Unit</th>
                      <th>Status</th>
                      <th>Planned rows</th>
                      <th>Shipment</th>
                      <th>Blockers</th>
                    </tr>
                  </thead>
                  <tbody>
                    {batchQueue.latestWave.items.map((item) => (
                      <tr key={item.unitKey}>
                        <td>{item.runOrder}</td>
                        <td>
                          <code>{item.unitKey}</code>
                        </td>
                        <td>{item.status}</td>
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
        ) : null}

        {batchQueue.latestExecution ? (
          <p className="admin-next-action">
            <strong>Latest execution:</strong> {batchQueue.latestExecution.executionKey} ·{" "}
            {batchQueue.latestExecution.status}
            {batchQueue.latestExecution.auditId
              ? ` · audit ${batchQueue.latestExecution.auditId}`
              : ""}
          </p>
        ) : null}

        <div className="admin-stat-grid">
          {batchCountries.map((country) => (
            <article className="admin-stat" key={country}>
              <span>{country}</span>
              <strong>{batchQueue.coverage.perCountry[country]}</strong>
              <p>planned units</p>
            </article>
          ))}
        </div>

        {batchQueue.blockerSummaries.length > 0 ? (
          <div className="admin-table-wrap">
            <table className="admin-target-table">
              <thead>
                <tr>
                  <th>Blocker</th>
                  <th>Units</th>
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

        <div className="admin-table-wrap">
          <table className="admin-target-table">
            <thead>
              <tr>
                <th>#</th>
                <th>Unit</th>
                <th>Country</th>
                <th>Geography</th>
                <th>Category</th>
                <th>Environment</th>
                <th>Priority</th>
                <th>Status</th>
                <th>Dry-run report</th>
              </tr>
            </thead>
            <tbody>
              {batchQueue.items.map((item) => (
                <tr key={item.unitKey}>
                  <td>{item.runOrder}</td>
                  <td>
                    <code>{item.unitKey}</code>
                  </td>
                  <td>{item.country}</td>
                  <td>{item.geography}</td>
                  <td>{item.category}</td>
                  <td>{item.targetEnvironment}</td>
                  <td>{item.priority}</td>
                  <td>{item.status}</td>
                  <td>
                    {item.dryRunReport
                      ? `${item.dryRunReport.rowsProcessed} rows · wroteToTarget=false`
                      : item.blockReasons.length > 0
                        ? item.blockReasons.join(", ")
                        : "—"}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      <section className="admin-section" aria-label="IP-18.7 autonomy">
        <div className="admin-section-heading admin-section-heading-compact">
          <div>
            <p className="admin-kicker">IP-18.7 · autonomy executor</p>
            <h2>Governed batch orchestration preview</h2>
          </div>
          <span className="admin-readonly-pill">
            {autonomySourceLabel(autonomySource)}
          </span>
        </div>
        {autonomyError ? (
          <p className="admin-command-result admin-command-result-error" role="alert">
            {autonomyError}
          </p>
        ) : null}
        <p className="admin-next-action">
          <strong>Next cycle decision:</strong> {autonomyView.nextCycle.decision} · phase{" "}
          {autonomyView.nextCycle.phase} · action {autonomyView.nextCycle.requiredAction}
          {autonomyView.nextCycle.pauseReason
            ? ` · paused: ${autonomyView.nextCycle.pauseReason}`
            : ""}
        </p>
        {autonomyView.nextCycle.recommendedAction ? (
          <p className="admin-next-action">
            <strong>Recommended:</strong> {autonomyView.nextCycle.recommendedAction.summary}
          </p>
        ) : null}
        <p className="admin-next-action">
          <strong>Execution channel:</strong> {autonomyView.executionChannelLabel}
        </p>
        {autonomyView.latestRun ? (
          <p className="admin-next-action">
            <strong>Latest run evidence:</strong> {autonomyView.latestRun.runKey} ·{" "}
            {autonomyView.latestRun.status}
            {autonomyView.latestRun.dryRunExecutionKey
              ? ` · dry-run ${autonomyView.latestRun.dryRunExecutionKey}`
              : ""}
            {autonomyView.latestRun.waveKey ? ` · wave ${autonomyView.latestRun.waveKey}` : ""}
            {autonomyView.latestRun.pauseReason ? ` · ${autonomyView.latestRun.pauseReason}` : ""}
          </p>
        ) : null}
        <div className="admin-stat-grid">
          <article className="admin-stat">
            <span>Policy</span>
            <strong>{autonomyView.policy?.policyKey ?? "—"}</strong>
            <p>
              {autonomyView.policy
                ? `${autonomyView.policy.status} · v${autonomyView.policy.policyVersion} · ${autonomyView.policy.targetEnvironment}`
                : "No active policy envelope"}
            </p>
          </article>
          <article className="admin-stat">
            <span>Ramp</span>
            <strong>{autonomyView.policy?.rampLabel ?? "—"}</strong>
            <p>
              {autonomyView.policy
                ? autonomyView.policy.recommendedNextRampMode
                  ? `next: ${autonomyView.policy.recommendedNextRampMode.replace(/_/g, " ")}`
                  : "terminal mode"
                : "No ramp envelope"}
            </p>
          </article>
          <article className="admin-stat">
            <span>Bounds</span>
            <strong>
              {autonomyView.policy
                ? `${autonomyView.policy.maxUnitsPerCycle}u / ${autonomyView.policy.maxRowsPerCycle}r`
                : "—"}
            </strong>
            <p>max units / rows per cycle</p>
          </article>
          <article className="admin-stat">
            <span>Selection</span>
            <strong>{autonomyView.nextCycle.selectedUnitKeys.length}</strong>
            <p>
              {autonomyView.nextCycle.maxUnitsApplied} units · {autonomyView.nextCycle.maxRowsApplied}{" "}
              rows applied
            </p>
          </article>
          <article className="admin-stat">
            <span>Latest run</span>
            <strong>{autonomyView.latestRun?.runKey ?? "—"}</strong>
            <p>
              {autonomyView.latestRun
                ? `${autonomyView.latestRun.phase} · ${autonomyView.latestRun.status}`
                : "No cycle ledger rows yet"}
            </p>
          </article>
        </div>
        {autonomyView.policy?.rampWarnings.length ? (
          <p className="admin-command-result admin-command-result-warning" role="alert">
            Ramp warning: {autonomyView.policy.rampWarnings.join("; ")}
          </p>
        ) : null}
        {autonomyView.nextCycle.selectedUnitKeys.length > 0 ? (
          <p className="admin-next-action">
            <strong>Selected units:</strong>{" "}
            {autonomyView.nextCycle.selectedUnitKeys.map((key) => (
              <code key={key}>{key} </code>
            ))}
          </p>
        ) : null}
        {(autonomyView.evidence.dryRunExecution || autonomyView.evidence.stagingWave) && (
          <p className="admin-next-action">
            <strong>Evidence:</strong>
            {autonomyView.evidence.dryRunExecution
              ? ` dry-run ${autonomyView.evidence.dryRunExecution.executionKey} (${autonomyView.evidence.dryRunExecution.status})`
              : ""}
            {autonomyView.evidence.stagingWave
              ? ` · wave ${autonomyView.evidence.stagingWave.waveKey} (${autonomyView.evidence.stagingWave.status})`
              : ""}
          </p>
        )}
        <ul>
          {autonomyView.safetySummary.map((line) => (
            <li key={line}>{line}</li>
          ))}
        </ul>
      </section>

      <section className="admin-section admin-policy-panel">
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

      <p className="provider-backlink admin-backlink">
        <Link href="/admin/providers">Back to provider control</Link>
      </p>
    </main>
  );
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

function progressiveSourceLabel(source: "live" | "sample" | "error"): string {
  if (source === "live") {
    return "Live control plane";
  }
  if (source === "error") {
    return "Live read failed · sample fallback";
  }
  return "Sample preview";
}

function batchQueueSourceLabel(source: "live" | "sample" | "error"): string {
  if (source === "live") {
    return "Live control plane";
  }
  if (source === "error") {
    return "Live read failed · sample fallback";
  }
  return "Sample preview · planning-only queue";
}

function autonomySourceLabel(source: "live" | "sample" | "error"): string {
  if (source === "live") {
    return "Live control plane";
  }
  if (source === "error") {
    return "Live read failed · sample fallback";
  }
  return "Sample preview · foundation only";
}
