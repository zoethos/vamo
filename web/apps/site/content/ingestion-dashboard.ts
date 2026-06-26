// Admin ingestion dashboard content.
//
// This module no longer hand-authors the dashboard. It reads through the
// platform read model: a control-plane snapshot is transformed into view state
// by `@vamo/ingestion-platform`. The page renders the result. The server-only
// control API owns mutations; the browser shell only posts commands through that
// authenticated API and never reads or writes control tables directly.
//
// No service-role secrets, DSNs, or control-table access live here.

import {
  buildIngestionDashboardView,
  sampleControlPlaneSnapshot,
} from "@vamo/ingestion-platform/read-model";
import type {
  IngestionStatus,
  IngestionTone,
} from "@vamo/ingestion-platform/read-model";

export type { IngestionStatus, IngestionTone };

const view = buildIngestionDashboardView(sampleControlPlaneSnapshot);

export const ingestionSignals = view.signals;
export const ingestionActions = view.actions;
export const ingestionInstances = view.instances;
export const ingestionTargets = view.targets;
export const ingestionEvents = view.events;
export const ingestionStats = view.stats;
export const ingestionPolicyLocks = view.policyLocks;
