"use client";

import { useRouter } from "next/navigation";
import { useCallback, useState } from "react";

import type { ScopeWorkflowContextPresentation } from "@confluendo/ingestion-platform/core/scope-workflow-presenter";
import type {
  WorkflowNavigatorPresentation,
  WorkflowNavigatorStageKey,
  WorkflowNavigatorStagePresentation,
  WorkflowStageNavigation
} from "@confluendo/ingestion-platform/core/workflow-navigator-presenter";
import type { ConsoleView } from "./ingestion-console-labels";

export type WorkflowRailPresentation =
  | WorkflowNavigatorPresentation
  | ScopeWorkflowContextPresentation;

type WorkflowNavigatorProps = {
  presentation: WorkflowRailPresentation;
  collapsed: boolean;
  mobile?: boolean;
  activeView: ConsoleView;
  onCollapse: () => void;
  onExpand: () => void;
  onNavigateView: (view: ConsoleView) => void;
  onBackToPortfolio?: () => void;
};

export function WorkflowNavigator({
  presentation,
  collapsed,
  mobile = false,
  activeView,
  onCollapse,
  onExpand,
  onNavigateView,
  onBackToPortfolio
}: WorkflowNavigatorProps) {
  const router = useRouter();

  if (presentation.mode === "scope") {
    return (
      <ScopeContextRail
        collapsed={collapsed}
        context={presentation}
        mobile={mobile}
        onBackToPortfolio={onBackToPortfolio}
        onCollapse={onCollapse}
        onExpand={onExpand}
      />
    );
  }

  if (collapsed && !mobile) {
    return (
      <aside className="admin-ux-workflow-rail-collapsed" aria-label="Workflow navigator collapsed">
        <button
          aria-expanded="false"
          aria-label="Expand workflow navigator"
          className="admin-ux-workflow-rail-toggle"
          onClick={onExpand}
          type="button"
        >
          ‹
        </button>
        {presentation.attentionCount > 0 ? (
          <span
            aria-label={`${presentation.attentionCount} actions needed`}
            className="admin-ux-workflow-rail-badge"
          >
            {presentation.attentionCount}
          </span>
        ) : null}
        <span className="admin-ux-workflow-rail-label">
          Workflow · {presentation.attentionCount} action
          {presentation.attentionCount === 1 ? "" : "s"} needed
        </span>
      </aside>
    );
  }

  return (
    <aside
      aria-label="Workflow navigator"
      className={mobile ? "admin-ux-workflow-navigator is-mobile" : "admin-ux-workflow-navigator"}
    >
      <div className="admin-ux-workflow-navigator-head">
        <div>
          <span className="admin-ux-workflow-kicker">Workflow navigator</span>
          <strong className="admin-ux-workflow-title">{presentation.title}</strong>
        </div>
        {!mobile ? (
          <button
            aria-expanded="true"
            aria-label="Collapse workflow navigator"
            className="admin-ux-workflow-collapse"
            onClick={onCollapse}
            type="button"
          >
            ›
          </button>
        ) : null}
      </div>

      {presentation.attentionSummary ? (
        <div className="admin-ux-workflow-attention" role="status">
          <span aria-hidden="true" className="admin-ux-workflow-attention-dot" />
          <div>
            <strong>
              {presentation.attentionCount} need{presentation.attentionCount === 1 ? "s" : ""}{" "}
              attention
            </strong>
            <p>{presentation.attentionSummary}</p>
            <button
              className="admin-ux-workflow-attention-action"
              onClick={() => onNavigateView("diagnostics")}
              type="button"
            >
              Open diagnostics →
            </button>
          </div>
        </div>
      ) : null}

      <ol className="admin-ux-workflow-stages">
        {presentation.stages.map((stage, index) => (
          <li key={stage.key}>
            {index > 0 ? <span aria-hidden="true" className="admin-ux-workflow-connector" /> : null}
            <WorkflowStageButton
              activeView={activeView}
              onNavigate={(navigation) => {
                if (navigation.kind === "view") {
                  onNavigateView(navigation.view as ConsoleView);
                  return;
                }
                router.push(navigation.href);
              }}
              stage={stage}
            />
          </li>
        ))}
      </ol>

      <p className="admin-ux-workflow-ownership">{presentation.ownershipNote}</p>
    </aside>
  );
}

function ScopeContextRail({
  context,
  collapsed,
  mobile,
  onBackToPortfolio,
  onCollapse,
  onExpand
}: {
  context: ScopeWorkflowContextPresentation;
  collapsed: boolean;
  mobile: boolean;
  onBackToPortfolio?: () => void;
  onCollapse: () => void;
  onExpand: () => void;
}) {
  const [copyState, setCopyState] = useState<"idle" | "copied">("idle");

  const copyUnitKey = useCallback(async () => {
    try {
      await navigator.clipboard.writeText(context.unitKey);
      setCopyState("copied");
      window.setTimeout(() => setCopyState("idle"), 1500);
    } catch {
      setCopyState("idle");
    }
  }, [context.unitKey]);

  if (collapsed && !mobile) {
    return (
      <aside className="admin-ux-workflow-rail-collapsed" aria-label="Scope context collapsed">
        <button
          aria-expanded="false"
          aria-label="Expand scope context"
          className="admin-ux-workflow-rail-toggle"
          onClick={onExpand}
          type="button"
        >
          ‹
        </button>
        <span className="admin-ux-workflow-rail-label">Scope · {context.friendlyName}</span>
      </aside>
    );
  }

  return (
    <aside
      aria-label="Scope context"
      className={
        mobile
          ? "admin-ux-workflow-navigator admin-ux-scope-context is-mobile"
          : "admin-ux-workflow-navigator admin-ux-scope-context"
      }
    >
      <div className="admin-ux-workflow-navigator-head">
        <div>
          <span className="admin-ux-workflow-kicker">Scope context</span>
          <strong className="admin-ux-workflow-title">{context.title}</strong>
        </div>
        {!mobile ? (
          <button
            aria-expanded="true"
            aria-label="Collapse scope context"
            className="admin-ux-workflow-collapse"
            onClick={onCollapse}
            type="button"
          >
            ›
          </button>
        ) : null}
      </div>

      {onBackToPortfolio ? (
        <button
          className="admin-ux-scope-back"
          onClick={onBackToPortfolio}
          type="button"
        >
          ← Back to portfolio
        </button>
      ) : null}

      <div className="admin-ux-scope-identity">
        <strong>{context.friendlyName}</strong>
        <div className="admin-ux-scope-key-row">
          <code className="admin-evidence-code">{context.unitKey}</code>
          <button
            aria-label="Copy scope key"
            className="admin-ux-scope-copy"
            onClick={() => void copyUnitKey()}
            type="button"
          >
            {copyState === "copied" ? "Copied" : "Copy"}
          </button>
        </div>
      </div>

      {context.displayFields.length > 0 ? (
        <dl className="admin-ux-scope-display-fields">
          {context.displayFields.map((field) => (
            <div key={field.key}>
              <dt>{field.label}</dt>
              <dd>
                <strong>{field.value}</strong>
                {field.detail ? <code className="admin-evidence-code">{field.detail}</code> : null}
              </dd>
            </div>
          ))}
        </dl>
      ) : null}

      <div className={`admin-ux-scope-status admin-ux-tone-${context.disposition.tone}`}>
        <span className="admin-ux-scope-status-label">Disposition</span>
        <strong>{context.disposition.label}</strong>
      </div>

      <div className={`admin-ux-scope-stage admin-ux-tone-${context.workflowStage.tone}`}>
        <span className="admin-ux-scope-status-label">Workflow position</span>
        <strong>{context.workflowStage.label}</strong>
        <p>{context.workflowStage.summary}</p>
      </div>

      <div className={`admin-ux-scope-lifecycle admin-ux-tone-${context.lifecycle.tone}`}>
        <span className="admin-ux-scope-status-label">Effective lifecycle</span>
        <strong>{context.lifecycle.label}</strong>
        {context.lifecycle.detail ? <p>{context.lifecycle.detail}</p> : null}
      </div>

      <p className="admin-ux-scope-next-action">
        <strong>Next safe action:</strong> {context.nextAction}
      </p>

      {context.sourceCandidates || context.expectedTargetWrites ? (
        <dl className="admin-ux-scope-metrics">
          {context.sourceCandidates ? (
            <div>
              <dt>Source candidates</dt>
              <dd>{context.sourceCandidates}</dd>
            </div>
          ) : null}
          {context.expectedTargetWrites ? (
            <div>
              <dt>Expected target writes</dt>
              <dd>{context.expectedTargetWrites}</dd>
            </div>
          ) : null}
        </dl>
      ) : null}

      <div className="admin-ux-scope-evidence">
        <span className="admin-ux-scope-status-label">Evidence trail</span>
        <ol className="admin-ux-scope-evidence-list">
          {context.evidenceTrail.map((entry) => (
            <li
              className={entry.available ? undefined : "is-unavailable"}
              key={entry.kind}
            >
              <div className="admin-ux-scope-evidence-head">
                <strong>{entry.label}</strong>
                <span>{entry.status}</span>
              </div>
              <p>{entry.detail}</p>
            </li>
          ))}
        </ol>
      </div>
    </aside>
  );
}

function WorkflowStageButton({
  stage,
  activeView,
  onNavigate
}: {
  stage: WorkflowNavigatorStagePresentation;
  activeView: ConsoleView;
  onNavigate: (navigation: WorkflowStageNavigation) => void;
}) {
  const isActive = stageMatchesView(stage.key, activeView);

  return (
    <button
      aria-current={isActive ? "step" : undefined}
      className={`admin-ux-workflow-stage admin-ux-tone-${stage.tone}${isActive ? " is-active" : ""}`}
      onClick={() => onNavigate(stage.navigation)}
      type="button"
    >
      <span className="admin-ux-workflow-stage-head">
        <span aria-hidden="true" className={`admin-ux-workflow-stage-dot admin-ux-tone-${stage.tone}`} />
        <span className="admin-ux-workflow-stage-label">{stage.label}</span>
      </span>
      <p className="admin-ux-workflow-stage-summary">{stage.summary}</p>
      <div className="admin-ux-workflow-stage-metrics">
        {stage.metrics.map((metric) => (
          <div key={`${stage.key}-${metric.label}`}>
            <strong>{metric.value}</strong>
            <span>{metric.label}</span>
          </div>
        ))}
      </div>
    </button>
  );
}

function stageMatchesView(stageKey: WorkflowNavigatorStageKey, activeView: ConsoleView): boolean {
  switch (stageKey) {
    case "queue_ready":
      return activeView === "queue";
    case "simulate":
      return activeView === "agent";
    case "verify_staging":
      return activeView === "staging";
    case "prepare_delivery":
    case "apply_vamo":
      return activeView === "delivery";
    case "needs_attention":
      return activeView === "diagnostics";
    default:
      return false;
  }
}
