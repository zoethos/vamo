"use client";

import { useRouter } from "next/navigation";

import type {
  WorkflowNavigatorPresentation,
  WorkflowNavigatorStageKey,
  WorkflowNavigatorStagePresentation,
  WorkflowStageNavigation
} from "@confluendo/ingestion-platform/core/workflow-navigator-presenter";
import type { ConsoleView } from "./ingestion-console-labels";

type WorkflowNavigatorProps = {
  presentation: WorkflowNavigatorPresentation;
  collapsed: boolean;
  mobile?: boolean;
  activeView: ConsoleView;
  onCollapse: () => void;
  onExpand: () => void;
  onNavigateView: (view: ConsoleView) => void;
};

export function WorkflowNavigator({
  presentation,
  collapsed,
  mobile = false,
  activeView,
  onCollapse,
  onExpand,
  onNavigateView
}: WorkflowNavigatorProps) {
  const router = useRouter();

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
