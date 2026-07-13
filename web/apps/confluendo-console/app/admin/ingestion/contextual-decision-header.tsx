"use client";

import Link from "next/link";
import type {
  WorkflowDecisionHeaderPresentation,
  WorkflowStageTone
} from "@confluendo/ingestion-platform/core/workflow-navigator-presenter";

type ContextualDecisionHeaderProps = {
  presentation: WorkflowDecisionHeaderPresentation;
};

export function ContextualDecisionHeader({
  presentation
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
        <Link
          className="admin-ux-decision-help-link"
          href={`/admin/help#${presentation.helpSection}`}
          title={`Open ${presentation.helpSectionLabel.toLowerCase()}`}
        >
          {presentation.helpSectionLabel} →
        </Link>
      </aside>
    </section>
  );
}

export type { WorkflowStageTone };
