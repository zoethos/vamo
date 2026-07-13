"use client";

import type {
  WorkflowDecisionHeaderPresentation,
  WorkflowStageTone
} from "@confluendo/ingestion-platform/core/workflow-navigator-presenter";

type ContextualDecisionHeaderProps = {
  presentation: WorkflowDecisionHeaderPresentation;
  onHelpAnchor?: () => void;
};

export function ContextualDecisionHeader({
  presentation,
  onHelpAnchor
}: ContextualDecisionHeaderProps) {
  return (
    <section
      aria-label="Current workflow context"
      className={`admin-ux-decision-header admin-ux-tone-${presentation.tone}`}
    >
      <div className="admin-ux-decision-copy">
        <span className="admin-ux-decision-kicker">{presentation.kicker}</span>
        <h2 className="admin-ux-decision-state">{presentation.state}</h2>
        <p className="admin-ux-decision-purpose">{presentation.purpose}</p>
      </div>
      <aside className="admin-ux-decision-action">
        <span className="admin-ux-decision-action-label">Next safe action</span>
        <strong>{presentation.nextAction}</strong>
        <button
          className="admin-ux-decision-help-link"
          onClick={onHelpAnchor}
          title="Help center arrives in UX-3. This control does not open a page yet."
          type="button"
        >
          {presentation.helpSectionLabel} →
        </button>
      </aside>
    </section>
  );
}

export type { WorkflowStageTone };
