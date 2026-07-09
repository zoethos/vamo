"use client";

import type { AutonomyDashboardView } from "@confluendo/ingestion-platform/core";
import {
  autonomySourceLabel,
  formatAgentAction,
  friendlyUnit
} from "./ingestion-console-labels";
import {
  humanizeAutonomyPhase,
  humanizeAutonomyRunStatus,
  presentAgentGuardrails,
  presentAgentPrimaryAction,
  presentAgentRunSurfaces,
  presentAgentWorkflowStatus,
  truncateEvidenceKey
} from "./agent-view-presenter";
import { CopyableCommandBlock, CopyableMonospace } from "./copyable-monospace";

type DashboardSource = "live" | "sample" | "error";

export function AgentView({
  autonomyView,
  autonomySource,
  autonomyError
}: {
  autonomyView: AutonomyDashboardView;
  autonomySource: DashboardSource;
  autonomyError?: string;
}) {
  const workflow = presentAgentWorkflowStatus(autonomyView);
  const primaryAction = presentAgentPrimaryAction(autonomyView);
  const guardrails = presentAgentGuardrails(autonomyView);
  const runSurfaces = presentAgentRunSurfaces();
  const selectedUnitKeys = autonomyView.nextCycle.selectedUnitKeys;
  const latestRun = autonomyView.latestRun;
  const rampWarnings = autonomyView.policy?.rampWarnings ?? [];

  return (
    <section className="admin-ux-section admin-ux-view-panel admin-agent-uex" aria-label="Agent operations">
      <div className="admin-section-heading admin-section-heading-compact">
        <div>
          <p className="admin-kicker">Agent operations</p>
          <h2>Bounded autonomous ingestion cycles</h2>
          <p className="admin-view-lead">
            The agent advances simulation, staging verification, and production delivery packages
            inside the approved policy envelope. Apply to Vamo stays operator- or consumer-owned.
          </p>
        </div>
        <span className="admin-readonly-pill">{autonomySourceLabel(autonomySource)}</span>
      </div>

      {autonomyError ? (
        <p className="admin-command-result admin-command-result-error" role="alert">
          {autonomyError}
        </p>
      ) : null}

      <div className={`admin-agent-uex-status admin-agent-uex-tone-${workflow.tone}`} role="status">
        <p className="admin-agent-uex-status-kicker">Current state</p>
        <h3>{workflow.title}</h3>
        <p>{workflow.detail}</p>
      </div>

      <section className="admin-agent-uex-panel" aria-labelledby="agent-next-action-heading">
        <div className="admin-agent-uex-panel-header">
          <h3 id="agent-next-action-heading">Recommended next action</h3>
        </div>
        <p className="admin-agent-uex-action-summary">{primaryAction.summary}</p>
        <dl className="admin-agent-uex-meta">
          <div>
            <dt>Execution channel</dt>
            <dd>{primaryAction.channelLabel}</dd>
          </div>
        </dl>
        {primaryAction.cliCommand ? (
          <>
            <p className="admin-agent-uex-command-note">
              Copy this into a trusted ops shell. The browser never executes this command.
            </p>
            <CopyableCommandBlock command={primaryAction.cliCommand} />
          </>
        ) : null}
        {primaryAction.runbookNote ? (
          <p className="admin-agent-uex-runbook-note">{primaryAction.runbookNote}</p>
        ) : null}
      </section>

      <section className="admin-agent-uex-panel" aria-labelledby="agent-run-surfaces-heading">
        <div className="admin-agent-uex-panel-header">
          <h3 id="agent-run-surfaces-heading">How this runs</h3>
        </div>
        <dl className="admin-agent-uex-run-surfaces">
          {runSurfaces.map((surface) => (
            <div key={surface.label}>
              <dt>{surface.label}</dt>
              <dd>
                <strong>{surface.value}</strong>
                <span>{surface.detail}</span>
              </dd>
            </div>
          ))}
        </dl>
      </section>

      <section className="admin-agent-uex-panel" aria-labelledby="agent-guardrails-heading">
        <div className="admin-agent-uex-panel-header">
          <h3 id="agent-guardrails-heading">Policy guardrails</h3>
        </div>
        <dl className="admin-agent-uex-guardrails">
          {guardrails.map((row) => (
            <div key={row.label}>
              <dt>{row.label}</dt>
              <dd>
                <strong>{row.value}</strong>
                {row.detail ? <span>{row.detail}</span> : null}
              </dd>
            </div>
          ))}
        </dl>
        {rampWarnings.length > 0 ? (
          <p className="admin-command-result admin-command-result-warning" role="alert">
            Ramp warning: {rampWarnings.join("; ")}
          </p>
        ) : null}
      </section>

      <section className="admin-agent-uex-panel" aria-labelledby="agent-scopes-heading">
        <div className="admin-agent-uex-panel-header">
          <h3 id="agent-scopes-heading">Selected scopes for next cycle</h3>
          <span className="admin-agent-uex-panel-count">{selectedUnitKeys.length}</span>
        </div>
        {selectedUnitKeys.length === 0 ? (
          <p className="admin-ux-empty">No scopes are selected for the next cycle yet.</p>
        ) : (
          <div className="admin-table-wrap">
            <table className="admin-target-table admin-agent-scope-table">
              <thead>
                <tr>
                  <th>Scope</th>
                  <th>Unit key</th>
                </tr>
              </thead>
              <tbody>
                {selectedUnitKeys.map((unitKey) => (
                  <tr key={unitKey}>
                    <td>
                      <strong>{friendlyUnit(unitKey)}</strong>
                    </td>
                    <td>
                      <CopyableMonospace value={unitKey} />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section className="admin-agent-uex-panel" aria-labelledby="agent-latest-run-heading">
        <div className="admin-agent-uex-panel-header">
          <h3 id="agent-latest-run-heading">Latest run</h3>
        </div>
        {!latestRun ? (
          <p className="admin-ux-empty">No agent cycle records yet.</p>
        ) : (
          <>
            <dl className="admin-agent-uex-meta admin-agent-uex-run-meta">
              <div>
                <dt>Status</dt>
                <dd>{humanizeAutonomyRunStatus(latestRun.status)}</dd>
              </div>
              <div>
                <dt>Phase</dt>
                <dd>{humanizeAutonomyPhase(latestRun.phase)}</dd>
              </div>
              <div>
                <dt>Action</dt>
                <dd>
                  {latestRun.recommendedAction &&
                  typeof latestRun.recommendedAction.action === "string"
                    ? formatAgentAction(latestRun.recommendedAction.action)
                    : "—"}
                </dd>
              </div>
              <div>
                <dt>Run evidence</dt>
                <dd>
                  <CopyableMonospace
                    value={latestRun.runKey}
                    displayValue={truncateEvidenceKey(latestRun.runKey)}
                    label={`Copy run key ${latestRun.runKey}`}
                  />
                </dd>
              </div>
            </dl>
            <details className="admin-agent-uex-evidence">
              <summary>Technical evidence</summary>
              <dl className="admin-agent-uex-evidence-list">
                <div>
                  <dt>Run key</dt>
                  <dd>
                    <CopyableMonospace value={latestRun.runKey} />
                  </dd>
                </div>
                {latestRun.dryRunExecutionKey ? (
                  <div>
                    <dt>Simulation execution</dt>
                    <dd>
                      <CopyableMonospace value={latestRun.dryRunExecutionKey} />
                    </dd>
                  </div>
                ) : null}
                {latestRun.waveKey ? (
                  <div>
                    <dt>Staging verification batch</dt>
                    <dd>
                      <CopyableMonospace value={latestRun.waveKey} />
                    </dd>
                  </div>
                ) : null}
                {latestRun.packageKey ? (
                  <div>
                    <dt>Production delivery package</dt>
                    <dd>
                      <CopyableMonospace value={latestRun.packageKey} />
                    </dd>
                  </div>
                ) : null}
                {latestRun.startedAt ? (
                  <div>
                    <dt>Started</dt>
                    <dd>{new Date(latestRun.startedAt).toLocaleString()}</dd>
                  </div>
                ) : null}
                {latestRun.completedAt ? (
                  <div>
                    <dt>Completed</dt>
                    <dd>{new Date(latestRun.completedAt).toLocaleString()}</dd>
                  </div>
                ) : null}
                {latestRun.pauseReason ? (
                  <div>
                    <dt>Pause reason</dt>
                    <dd>{latestRun.pauseReason}</dd>
                  </div>
                ) : null}
              </dl>
              {(autonomyView.evidence.dryRunExecution || autonomyView.evidence.stagingWave) && (
                <dl className="admin-agent-uex-evidence-list">
                  {autonomyView.evidence.dryRunExecution ? (
                    <div>
                      <dt>Linked simulation execution</dt>
                      <dd>
                        <CopyableMonospace
                          value={autonomyView.evidence.dryRunExecution.executionKey}
                        />{" "}
                        ({autonomyView.evidence.dryRunExecution.status})
                      </dd>
                    </div>
                  ) : null}
                  {autonomyView.evidence.stagingWave ? (
                    <div>
                      <dt>Linked staging verification batch</dt>
                      <dd>
                        <CopyableMonospace value={autonomyView.evidence.stagingWave.waveKey} /> (
                        {autonomyView.evidence.stagingWave.status})
                      </dd>
                    </div>
                  ) : null}
                </dl>
              )}
              <ul className="admin-agent-uex-safety-list">
                {autonomyView.safetySummary.map((line) => (
                  <li key={line}>{line}</li>
                ))}
              </ul>
            </details>
          </>
        )}
      </section>
    </section>
  );
}
