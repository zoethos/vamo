"use client";

import {
  buildDeliveryTerminalStatus,
  buildDeliveryWhatToDoNext,
  DELIVERY_COMPACT_INTRO,
  DELIVERY_LONG_RUNNING_COPY,
  DELIVERY_PARTIAL_BATCH_APPLY_COPY,
  DELIVERY_REFRESH_TELEMETRY_SAFETY,
  DELIVERY_STATE_TERMINOLOGY,
  DELIVERY_WORKFLOW_STEPS,
  deliveryWorkflowStepLabel,
  resolveDeliveryWorkflowHighlight,
  type DeliveryWorkflowGuideInput
} from "@confluendo/ingestion-platform/core/delivery-workflow-presenter";

export type DeliveryWorkflowGuideProps = DeliveryWorkflowGuideInput;

export function DeliveryWorkflowGuide(props: DeliveryWorkflowGuideProps) {
  const highlight = resolveDeliveryWorkflowHighlight(props);
  const whatToDoNext = buildDeliveryWhatToDoNext(props);
  const terminalStatus = buildDeliveryTerminalStatus(props);
  const currentLabel = deliveryWorkflowStepLabel(highlight);
  const terminologyDefaultOpen = props.appliedCount === 0;

  return (
    <section className="admin-delivery-workflow-guide" aria-label="Delivery workflow guide">
      <ol className="admin-delivery-workflow-strip">
        {DELIVERY_WORKFLOW_STEPS.map((step) => {
          const isCurrent = step.key === highlight;
          const isUnknownCurrent = highlight === "apply_state_unknown" && step.key === "delivered_to_inbox";
          return (
            <li
              key={step.key}
              className={`admin-delivery-workflow-step${isCurrent || isUnknownCurrent ? " is-current" : ""}`}
              aria-current={isCurrent ? "step" : undefined}
            >
              <span className="admin-delivery-workflow-step-label">{step.label}</span>
            </li>
          );
        })}
      </ol>

      {highlight === "apply_state_unknown" ? (
        <p className="admin-delivery-workflow-unknown" role="status">
          Current state: <strong>{currentLabel}</strong>
        </p>
      ) : (
        <p className="admin-delivery-workflow-current" role="status">
          Current state: <strong>{currentLabel}</strong>
        </p>
      )}

      <p className="admin-delivery-workflow-intro">{DELIVERY_COMPACT_INTRO}</p>

      <div className="admin-delivery-workflow-safety admin-command-result admin-command-result-watch">
        <strong>Safe recovery step</strong>
        <span>{DELIVERY_REFRESH_TELEMETRY_SAFETY}</span>
      </div>

      {terminalStatus ? (
        <div className="admin-delivery-workflow-terminal admin-command-result admin-command-result-ok" role="status">
          <strong>{terminalStatus}</strong>
        </div>
      ) : null}

      <details className="admin-evidence-details admin-delivery-workflow-details" open={terminologyDefaultOpen}>
        <summary>Package state terminology</summary>
        <div className="admin-table-wrap">
          <table className="admin-target-table admin-delivery-workflow-table">
            <thead>
              <tr>
                <th>State</th>
                <th>Meaning</th>
                <th>Why it matters</th>
                <th>Operator action</th>
              </tr>
            </thead>
            <tbody>
              {DELIVERY_STATE_TERMINOLOGY.map((row) => (
                <tr key={row.state}>
                  <td>
                    <strong>{row.state}</strong>
                  </td>
                  <td>{row.meaning}</td>
                  <td>{row.whyItMatters}</td>
                  <td>{row.operatorAction}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </details>

      <details className="admin-evidence-details admin-delivery-workflow-details">
        <summary>Prerequisites and safeguards</summary>
        <div className="admin-delivery-workflow-section">
          <h4>Before a scope can be eligible for package</h4>
          <ul className="admin-delivery-workflow-list">
            <li>The scope completed dry-run successfully and wrote nothing to the target.</li>
            <li>Staging verification succeeded and evidence still matches package content.</li>
            <li>The target schema contract is compatible and source rights allow package delivery.</li>
            <li>No active blockers remain and the scope is not already in an active package wave.</li>
          </ul>
          <p>
            A scope becomes eligible only after Confluendo proves the data in dry-run and staging
            verification. If a scope is missing here, check the Staging tab first.
          </p>
        </div>
        <div className="admin-delivery-workflow-section">
          <h4>Before delivery to inbox</h4>
          <ul className="admin-delivery-workflow-list">
            <li>A production package wave was approved and has not expired (about 15 minutes).</li>
            <li>Package content still matches the staged content hash.</li>
            <li>Delivery runs through the confirmation-gated production inbox path.</li>
          </ul>
          <p>Delivery puts the package into the consumer inbox only. It does not apply data to product tables.</p>
        </div>
        <div className="admin-delivery-workflow-section">
          <h4>Before apply to Vamo</h4>
          <ul className="admin-delivery-workflow-list">
            <li>The package is delivered to the Vamo production inbox.</li>
            <li>Apply preflight can read the package and at least one item is still pending.</li>
            <li>The operator has admin access, AAL2, fresh MFA when required, and an audit reason.</li>
          </ul>
          <p>
            Apply is the consumer-owned step. For Vamo, this calls Vamo&apos;s approved inbox apply
            function and writes to Vamo product tables only through that function.
          </p>
        </div>
        <div className="admin-delivery-workflow-section">
          <h4>Long-running and partial-batch apply</h4>
          <p>{DELIVERY_LONG_RUNNING_COPY}</p>
          <p>{DELIVERY_PARTIAL_BATCH_APPLY_COPY}</p>
        </div>
      </details>

      <details className="admin-evidence-details admin-delivery-workflow-details" open>
        <summary>What to do next</summary>
        <p className="admin-delivery-workflow-next-action">{whatToDoNext}</p>
        <p className="admin-delivery-workflow-page-scope">
          This page controls production package waves. Confluendo owns package preparation and inbox
          delivery. The consumer owns product-table apply.
        </p>
      </details>
    </section>
  );
}
