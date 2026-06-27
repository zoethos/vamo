// IP-14 progressive dry-run board content.
//
// Thin consumer view: it reads through the platform read model
// (`@vamo/ingestion-platform/progressive-read-model`) and exposes the resulting
// view to the admin page. All scoring, scheduling, and run policy live in the
// platform core. No control-table access, DSNs, or service-role secrets here.
//
// The bundled sample snapshot renders the board before a live control API feeds
// real proposals/run reports through the same pure transform.

import {
  buildProgressiveRunView,
  sampleProgressiveRunSnapshot,
} from "@vamo/ingestion-platform/progressive-read-model";
import type {
  ProgressiveBacklogRow,
  ProgressiveRunView,
} from "@vamo/ingestion-platform/progressive-read-model";

export type { ProgressiveBacklogRow, ProgressiveRunView };

const view: ProgressiveRunView = buildProgressiveRunView(sampleProgressiveRunSnapshot);

export const progressiveRows = view.rows;
export const progressiveSummary = view.summary;
export const progressiveNextAction = view.nextAction;
