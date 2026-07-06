/**
 * Autonomy cycle telemetry contract (IP-18.7).
 *
 * Reserved event names for `ingestion_events` and cycle audit linkage. This slice
 * defines types/constants only — live emission awaits a future executor loop.
 */

export const AUTONOMY_CYCLE_EVENT_NAMES = [
  "autonomy.cycle.started",
  "autonomy.cycle.advanced",
  "autonomy.cycle.paused",
  "autonomy.cycle.completed",
  "autonomy.cycle.failed",
  "autonomy.action.applied"
] as const;

export type AutonomyCycleEventName = (typeof AUTONOMY_CYCLE_EVENT_NAMES)[number];

export interface AutonomyCycleTelemetryPayload {
  eventName: AutonomyCycleEventName;
  policyId?: string;
  policyKey?: string;
  policyVersion?: number;
  runKey?: string;
  phase?: string;
  projectKey?: string;
  sourceKey?: string;
  targetKey?: string;
  targetEnvironment?: string;
  actorType?: string;
  actorId?: string;
  decision?: string;
  requiredAction?: string;
  selectedUnitKeys?: string[];
  pauseReason?: string;
  recommendedAction?: Record<string, unknown>;
  evidence?: Record<string, unknown>;
}

export function isAutonomyCycleEventName(value: string): value is AutonomyCycleEventName {
  return (AUTONOMY_CYCLE_EVENT_NAMES as readonly string[]).includes(value);
}
