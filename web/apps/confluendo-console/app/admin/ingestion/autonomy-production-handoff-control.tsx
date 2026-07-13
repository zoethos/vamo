"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import type { AdminAssuranceLevel, AdminRole } from "@confluendo/ingestion-platform/admin-auth";
import type {
  AutonomyProductionHandoffCardPresentation,
  AutonomyProductionHandoffState
} from "@confluendo/ingestion-platform/core";

type DashboardSource = "live" | "sample" | "error";

type HandoffContext = {
  role: AdminRole;
  assuranceLevel: AdminAssuranceLevel;
  source: DashboardSource;
};

type Decision =
  | { state: "idle" }
  | { state: "running"; requestedEnabled: boolean }
  | {
      state: "changed";
      direction: "enable" | "disable";
      toEnabled: boolean;
      auditId: string;
      policyVersion: number;
    }
  | { state: "blocked"; blocks: string[] }
  | { state: "error"; message: string; code?: string };

const blockLabels: Record<string, string> = {
  same_state: "Production handoff is already in the requested state.",
  missing_audit_reason: "Audit reason is required.",
  missing_actor_identity: "An authenticated operator identity is required.",
  actor_not_admin: "Production handoff changes require the admin role.",
  fresh_step_up_required: "Enabling production handoff requires a fresh MFA check.",
  production_handoff_conflict: "The production handoff state changed. Refresh before trying again.",
  confirmed_state_mismatch: "Selected target state must match the requested change."
};

const freshStepUpHref =
  "/admin/mfa/challenge?reason=fresh_step_up_required&next=%2Fadmin%2Fingestion";

export function AutonomyProductionHandoffControl({
  projectKey,
  policyKey,
  handoffCard,
  context
}: {
  projectKey: string;
  policyKey: string;
  handoffCard: AutonomyProductionHandoffCardPresentation;
  context: HandoffContext;
}) {
  const [auditReason, setAuditReason] = useState("");
  const [confirmedState, setConfirmedState] = useState<AutonomyProductionHandoffState | "">("");
  const [decision, setDecision] = useState<Decision>({ state: "idle" });
  const inFlightRef = useRef(false);
  const router = useRouter();

  const requestedEnabled = !handoffCard.enabled;
  const requestedState = handoffCard.requestedState;
  const pending = decision.state === "running";
  const disabledReason =
    handoffDisabledReason(context, requestedEnabled) ??
    (!auditReason.trim() ? "Audit reason is required." : undefined) ??
    (confirmedState !== requestedState
      ? `Select ${handoffCard.requestedStateLabel.toLowerCase()} in the confirmation dropdown.`
      : undefined);

  async function submitChange() {
    if (inFlightRef.current) {
      return;
    }
    if (!auditReason.trim()) {
      setDecision({ state: "error", message: "Audit reason is required." });
      return;
    }
    if (confirmedState !== requestedState) {
      setDecision({
        state: "error",
        message: `Select ${handoffCard.requestedStateLabel.toLowerCase()} to confirm.`
      });
      return;
    }

    inFlightRef.current = true;
    setDecision({ state: "running", requestedEnabled });

    try {
      const response = await fetch("/api/admin/ingestion/autonomy/production-handoff", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          projectKey,
          policyKey,
          expectedEnabled: handoffCard.enabled,
          requestedEnabled,
          auditReason: auditReason.trim(),
          confirmedState
        })
      });
      const payload = (await response.json().catch(() => null)) as
        | {
            ok: true;
            decision: "enable" | "disable";
            toEnabled: boolean;
            policyVersion: number;
            auditId: string;
          }
        | {
            ok: false;
            decision?: "blocked";
            blocks?: { code: string }[];
            error?: string;
            code?: string;
          }
        | null;

      if (!payload) {
        setDecision({ state: "error", message: "The production handoff request failed." });
        return;
      }

      if (payload.ok) {
        setDecision({
          state: "changed",
          direction: payload.decision,
          toEnabled: payload.toEnabled,
          policyVersion: payload.policyVersion,
          auditId: payload.auditId
        });
        setAuditReason("");
        setConfirmedState("");
        router.refresh();
        return;
      }

      if (payload.decision === "blocked" && Array.isArray(payload.blocks)) {
        const blocks = payload.blocks.map((block) => block.code);
        if (blocks.includes("fresh_step_up_required")) {
          window.location.assign(freshStepUpHref);
          return;
        }
        setDecision({ state: "blocked", blocks });
        return;
      }

      setDecision({
        state: "error",
        message: payload.error ?? "The production handoff request was refused.",
        code: payload.code
      });
    } catch {
      setDecision({ state: "error", message: "The production handoff request failed to send." });
    } finally {
      inFlightRef.current = false;
    }
  }

  return (
    <section
      className={`admin-agent-uex-panel admin-agent-handoff-panel admin-agent-handoff-${handoffCard.tone}`}
      aria-labelledby="agent-production-handoff-heading"
    >
      <div className="admin-agent-uex-panel-header">
        <h3 id="agent-production-handoff-heading">Production package handoff</h3>
        <span className={`admin-delivery-state admin-delivery-state-${handoffCard.tone}`}>
          {handoffCard.stateLabel}
        </span>
      </div>

      <p className="admin-agent-ramp-note">{handoffCard.description}</p>

      <div className="admin-agent-handoff-grid">
        <div>
          <h4>What autonomy may do</h4>
          <ul>
            {handoffCard.allowedActions.map((action) => (
              <li key={action}>{action}</li>
            ))}
          </ul>
        </div>
        <div>
          <h4>What stays manual</h4>
          <ul>
            {handoffCard.deniedActions.map((action) => (
              <li key={action}>{action}</li>
            ))}
          </ul>
        </div>
        <div>
          <h4>Safeguards</h4>
          <ul>
            {handoffCard.safeguards.map((safeguard) => (
              <li key={safeguard}>{safeguard}</li>
            ))}
          </ul>
        </div>
      </div>

      <div className="admin-agent-ramp-fields">
        <label>
          <span>Audit reason</span>
          <textarea
            value={auditReason}
            onChange={(event) => setAuditReason(event.target.value)}
            rows={2}
            maxLength={320}
            placeholder={
              requestedEnabled
                ? "Why should autonomy be allowed to approve and deliver production packages now?"
                : "Why should production package handoff be disabled now?"
            }
            disabled={pending}
          />
        </label>
        <label>
          <span>Confirm target state</span>
          <select
            value={confirmedState}
            onChange={(event) =>
              setConfirmedState(event.target.value as AutonomyProductionHandoffState | "")
            }
            disabled={pending}
          >
            <option value="">Select target state</option>
            <option value={requestedState}>{handoffCard.requestedStateLabel}</option>
          </select>
        </label>
      </div>

      <div className="admin-action-row admin-agent-ramp-actions">
        <button
          type="button"
          className={
            requestedEnabled
              ? "admin-command admin-command-primary admin-stateful-command"
              : "admin-command admin-command-neutral admin-stateful-command"
          }
          data-state={pending ? "busy" : disabledReason ? "unavailable" : "ready"}
          onClick={() => void submitChange()}
          disabled={Boolean(disabledReason) || pending}
          title={disabledReason ?? undefined}
        >
          {pending
            ? requestedEnabled
              ? "Enabling production handoff..."
              : "Disabling production handoff..."
            : handoffCard.requestedStateLabel}
        </button>
        {disabledReason ? (
          <p className="admin-action-status" data-state="unavailable">
            Policy change unavailable: {disabledReason}
          </p>
        ) : null}
      </div>

      <DecisionView decision={decision} />
    </section>
  );
}

function DecisionView({ decision }: { decision: Decision }) {
  if (decision.state === "idle" || decision.state === "running") {
    return null;
  }
  if (decision.state === "changed") {
    return (
      <div className="admin-command-result admin-command-result-ok" role="status">
        <strong>Production handoff policy updated</strong>
        <span>
          {decision.toEnabled ? "Enabled" : "Disabled"} · policy v{decision.policyVersion} · audit
          id {decision.auditId}
        </span>
        <span>Apply to Vamo remains operator-controlled.</span>
      </div>
    );
  }
  if (decision.state === "blocked") {
    return (
      <div className="admin-command-result admin-command-result-error" role="alert">
        <strong>Production handoff change blocked</strong>
        <ul>
          {decision.blocks.map((code) => (
            <li key={code}>{blockLabels[code] ?? code}</li>
          ))}
        </ul>
      </div>
    );
  }
  return (
    <div className="admin-command-result admin-command-result-error" role="alert">
      <strong>{decision.message}</strong>
    </div>
  );
}

function handoffDisabledReason(
  context: HandoffContext,
  requestedEnabled: boolean
): string | undefined {
  if (context.source === "error") {
    return "Live control-plane read failed.";
  }
  if (context.source !== "live") {
    return "Production handoff changes require a live control plane.";
  }
  if (context.role !== "admin") {
    return "Production handoff changes require the admin role.";
  }
  if (requestedEnabled && context.assuranceLevel !== "aal2") {
    return "Enabling production handoff requires verified MFA.";
  }
  return undefined;
}
