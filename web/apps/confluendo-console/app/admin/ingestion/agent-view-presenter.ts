import type {
  AutonomyDashboardView,
  AutonomyExecutionChannel
} from "@confluendo/ingestion-platform/core";
import { formatAgentAction } from "./ingestion-console-labels";

export type AgentWorkflowTone = "ready" | "waiting" | "blocked" | "completed";

export interface AgentWorkflowStatus {
  tone: AgentWorkflowTone;
  title: string;
  detail: string;
}

export interface AgentPrimaryAction {
  summary: string;
  channelLabel: string;
  channel: AutonomyExecutionChannel;
  cliCommand?: string;
  runbookNote?: string;
}

export interface AgentGuardrailRow {
  label: string;
  value: string;
  detail?: string;
}

export function presentAgentWorkflowStatus(view: AutonomyDashboardView): AgentWorkflowStatus {
  const { nextCycle, latestRun } = view;

  if (nextCycle.decision === "pause" || nextCycle.requiredAction === "pause_for_blocker") {
    return {
      tone: "blocked",
      title: titleForPause(nextCycle.pauseReasonCode, nextCycle.requiredAction),
      detail:
        nextCycle.pauseReason ??
        nextCycle.recommendedAction?.summary ??
        "The agent cannot advance until the blocking condition is resolved."
    };
  }

  if (nextCycle.decision === "no_op" && latestRun?.status === "completed") {
    return {
      tone: "completed",
      title: "Cycle completed",
      detail: "The latest agent cycle finished without further autonomous work in this pass."
    };
  }

  if (nextCycle.decision === "no_op" || nextCycle.requiredAction === "wait_for_human") {
    return {
      tone: "waiting",
      title: "Waiting for operator",
      detail:
        nextCycle.recommendedAction?.summary ??
        "An operator decision or policy change is needed before the next cycle can run."
    };
  }

  return {
    tone: "ready",
    title: titleForRequiredAction(nextCycle.requiredAction),
    detail: supportingDetailForAction(nextCycle.requiredAction, nextCycle.phase)
  };
}

export function presentAgentPrimaryAction(view: AutonomyDashboardView): AgentPrimaryAction {
  const summary =
    view.nextCycle.recommendedAction?.summary ??
    formatAgentAction(view.nextCycle.requiredAction);

  const channel = view.executionChannel;
  const channelLabel = humanizeExecutionChannel(channel);

  if (channel === "autonomy_cli") {
    return {
      summary,
      channelLabel,
      channel,
      cliCommand: buildAutonomyCliCommand(view, true)
    };
  }

  if (channel === "human_runbook") {
    return {
      summary,
      channelLabel,
      channel,
      runbookNote: humanizeRunbookChannel(view)
    };
  }

  return {
    summary,
    channelLabel,
    channel
  };
}

export function presentAgentGuardrails(view: AutonomyDashboardView): AgentGuardrailRow[] {
  const policy = view.policy;
  const handoff = presentProductionHandoff(view);
  const consumerApply = presentConsumerApplyAutonomy();

  if (!policy) {
    return [
      { label: "Operating policy", value: "Not configured", detail: "No active policy envelope." },
      { label: "Ramp mode", value: "—" },
      { label: "Cycle bounds", value: "—" },
      handoff,
      consumerApply
    ];
  }

  return [
    {
      label: "Policy key",
      value: policy.policyKey,
      detail: `Version ${policy.policyVersion} · ${policy.status} · ${policy.targetEnvironment}`
    },
    {
      label: "Ramp mode",
      value: policy.rampLabel,
      detail: policy.recommendedNextRampMode
        ? `Next ramp: ${formatAgentAction(policy.recommendedNextRampMode)}`
        : policy.rampDescription
    },
    {
      label: "Cycle bounds",
      value: `${policy.maxUnitsPerCycle} scopes / ${policy.maxRowsPerCycle} target writes`,
      detail: `This cycle applies ${view.nextCycle.maxUnitsApplied} scopes · ${view.nextCycle.maxRowsApplied} target writes`
    },
    handoff,
    consumerApply
  ];
}

export function presentProductionHandoff(view: AutonomyDashboardView): AgentGuardrailRow {
  const { nextCycle } = view;

  if (nextCycle.pauseReasonCode === "production_inbox_not_executable") {
    return {
      label: "Production handoff",
      value: "Not allowed",
      detail:
        nextCycle.pauseReason ??
        "Production delivery package actions are not enabled for this policy envelope."
    };
  }

  if (nextCycle.requiredAction === "waiting_for_ip18_6") {
    return {
      label: "Production handoff",
      value: "Not available",
      detail: "Production delivery package capability is not active for this policy yet."
    };
  }

  if (
    nextCycle.requiredAction === "approve_production_package_wave" ||
    nextCycle.requiredAction === "deliver_production_package_wave"
  ) {
    return {
      label: "Production handoff",
      value: "Allowed",
      detail: "Policy permits autonomous production delivery package actions in this cycle."
    };
  }

  if (nextCycle.phase === "production_inbox" && nextCycle.decision === "continue") {
    return {
      label: "Production handoff",
      value: "Allowed",
      detail: "The agent is operating in the production delivery phase."
    };
  }

  return {
    label: "Production handoff",
    value: "Not in scope",
    detail:
      "Current cycle focuses on simulation or staging verification. Production handoff activates after staging proof."
  };
}

export function presentConsumerApplyAutonomy(): AgentGuardrailRow {
  return {
    label: "Apply to Vamo",
    value: "Operator-owned",
    detail: "Consumer apply autonomy is disabled by design. Apply to Vamo remains a gated human or consumer control."
  };
}

export function truncateEvidenceKey(value: string, maxLength = 32): string {
  if (value.length <= maxLength) {
    return value;
  }
  const head = Math.max(10, Math.floor((maxLength - 1) / 2));
  const tail = Math.max(8, maxLength - head - 1);
  return `${value.slice(0, head)}…${value.slice(-tail)}`;
}

export function humanizeAutonomyPhase(phase: string): string {
  return formatAgentAction(phase);
}

export function humanizeAutonomyRunStatus(status: string): string {
  if (status === "completed") {
    return "Completed";
  }
  if (status === "paused") {
    return "Paused";
  }
  if (status === "running") {
    return "Running";
  }
  if (status === "failed") {
    return "Failed";
  }
  return formatAgentAction(status);
}

function titleForRequiredAction(action: string): string {
  switch (action) {
    case "schedule_dry_run":
      return "Ready to schedule simulation";
    case "execute_dry_run":
      return "Ready to run simulation";
    case "approve_or_execute_staging_wave_later":
      return "Ready for staging verification";
    case "approve_production_package_wave":
      return "Ready to approve production delivery package";
    case "deliver_production_package_wave":
      return "Ready to deliver package";
    case "apply_consumer_package":
      return "Waiting for Apply to Vamo";
    case "waiting_for_ip18_6":
      return "Waiting for production delivery capability";
    default:
      return formatAgentAction(action);
  }
}

function titleForPause(pauseReasonCode: string | undefined, requiredAction: string): string {
  if (requiredAction === "pause_for_blocker" || pauseReasonCode === "queue_blockers") {
    return "Blocked — queue needs attention";
  }
  if (pauseReasonCode === "policy_missing" || pauseReasonCode === "policy_inactive") {
    return "Waiting for operator";
  }
  if (pauseReasonCode === "rolling_limit_exceeded" || pauseReasonCode === "bounds_exceeded") {
    return "Blocked — cycle limits reached";
  }
  if (pauseReasonCode === "production_inbox_not_executable") {
    return "Blocked — production handoff not permitted";
  }
  return "Waiting for operator";
}

function supportingDetailForAction(action: string, phase: string): string {
  switch (action) {
    case "schedule_dry_run":
      return "The agent can queue the next bounded simulation pass for selected scopes.";
    case "execute_dry_run":
      return "Simulation evidence is ready to be collected without writing to staging or production.";
    case "approve_or_execute_staging_wave_later":
      return "Staging verification can be approved or executed after simulation evidence is clean.";
    case "approve_production_package_wave":
      return "Staging-verified scopes can move into a bounded production delivery package approval.";
    case "deliver_production_package_wave":
      return "An approved production delivery package can be handed to the consumer inbox.";
    case "apply_consumer_package":
      return "A delivered package is waiting for the gated Apply to Vamo control.";
    default:
      return `Operating in ${humanizeAutonomyPhase(phase)}.`;
  }
}

function humanizeExecutionChannel(channel: AutonomyExecutionChannel): string {
  if (channel === "autonomy_cli") {
    return "Autonomy CLI (preview or execute)";
  }
  if (channel === "human_runbook") {
    return "Human confirmation runbook";
  }
  return "No autonomous execution channel";
}

function humanizeRunbookChannel(view: AutonomyDashboardView): string {
  if (view.nextCycle.requiredAction === "apply_consumer_package") {
    return "Use the Delivery tab apply-to-Vamo control after confirming package evidence.";
  }
  if (view.nextCycle.requiredAction === "approve_or_execute_staging_wave_later") {
    return "Use the Staging tab to approve or execute staging verification when evidence is ready.";
  }
  return "Follow the confirmation-gated runbook for this action. The autonomy CLI does not execute it directly.";
}

function buildAutonomyCliCommand(view: AutonomyDashboardView, execute: boolean): string {
  const projectKey = view.projectKey;
  const policyKey = view.policy?.policyKey ?? "<policy-key>";
  const base = `node .\\packages\\ingestion-platform\\scripts\\run-ip18-autonomy-cycle.mjs \`
  --project-key ${projectKey} \`
  --policy-key ${policyKey}`;
  if (!execute) {
    return base;
  }
  return `$env:CONFIRM_CONFLUENDO_AUTONOMY_CYCLE="YES"

node .\\packages\\ingestion-platform\\scripts\\run-ip18-autonomy-cycle.mjs \`
  --execute \`
  --project-key ${projectKey} \`
  --policy-key ${policyKey}

Remove-Item Env:\\CONFIRM_CONFLUENDO_AUTONOMY_CYCLE -ErrorAction SilentlyContinue`;
}
