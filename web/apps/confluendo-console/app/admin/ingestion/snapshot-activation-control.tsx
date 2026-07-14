"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import type { AdminAssuranceLevel, AdminRole } from "@confluendo/ingestion-platform/admin-auth";
import type { SnapshotActivationCardPresentation } from "@confluendo/ingestion-platform/core";

type DashboardSource = "live" | "sample" | "error";

type ActivationContext = {
  role: AdminRole;
  assuranceLevel: AdminAssuranceLevel;
  source: DashboardSource;
};

type Decision =
  | { state: "idle" }
  | { state: "running" }
  | { state: "requested"; requestId: string; auditId: string; releaseId: string }
  | { state: "blocked"; blocks: string[] }
  | { state: "error"; message: string };

const confirmationState = "request_activation" as const;
const freshStepUpHref =
  "/admin/mfa/challenge?reason=fresh_step_up_required&next=%2Fadmin%2Fingestion";

const blockLabels: Record<string, string> = {
  missing_audit_reason: "Audit reason is required.",
  missing_actor_identity: "An authenticated operator identity is required.",
  actor_not_admin: "Activation requests require the admin role.",
  fresh_step_up_required: "Activation requests require a recent MFA verification.",
  activation_not_ready: "A registered release is not ready for activation.",
  activation_request_already_active: "An activation request is already in progress for this batch plan."
};

export function SnapshotActivationControl({
  projectKey,
  activationCard,
  context,
  freshStepUpExpiresAt,
  serverNowMs
}: {
  projectKey: string;
  activationCard: SnapshotActivationCardPresentation;
  context: ActivationContext;
  freshStepUpExpiresAt?: string;
  serverNowMs: number;
}) {
  const [auditReason, setAuditReason] = useState("");
  const [confirmedState, setConfirmedState] = useState("");
  const [decision, setDecision] = useState<Decision>({ state: "idle" });
  const inFlightRef = useRef(false);
  const router = useRouter();
  const pending = decision.state === "running";
  const stepUpFresh =
    freshStepUpExpiresAt !== undefined && Date.parse(freshStepUpExpiresAt) > serverNowMs;
  const disabledReason = activationDisabledReason({
    context,
    activationCard,
    stepUpFresh,
    auditReason,
    confirmedState
  });

  async function submitRequest() {
    if (inFlightRef.current || disabledReason) return;
    inFlightRef.current = true;
    setDecision({ state: "running" });
    try {
      const response = await fetch("/api/admin/ingestion/snapshot-activation/request", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          projectKey,
          auditReason: auditReason.trim(),
          confirmedState: confirmationState
        })
      });
      const payload = (await response.json().catch(() => null)) as
        | { ok: true; requestId: string; auditId: string; releaseId: string }
        | { ok: false; decision?: "blocked"; blocks?: { code: string }[]; error?: string }
        | null;
      if (!payload) {
        setDecision({ state: "error", message: "The activation request failed." });
        return;
      }
      if (payload.ok) {
        setDecision({
          state: "requested",
          requestId: payload.requestId,
          auditId: payload.auditId,
          releaseId: payload.releaseId
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
      setDecision({ state: "error", message: payload.error ?? "The activation request was refused." });
    } catch {
      setDecision({ state: "error", message: "The activation request failed to send." });
    } finally {
      inFlightRef.current = false;
    }
  }

  return (
    <section
      className={`admin-agent-uex-panel admin-agent-handoff-panel admin-agent-handoff-${activationCard.tone}`}
      aria-labelledby="snapshot-activation-heading"
    >
      <div className="admin-agent-uex-panel-header">
        <h3 id="snapshot-activation-heading">{activationCard.title}</h3>
        <span className={`admin-delivery-state admin-delivery-state-${activationCard.tone}`}>
          {activationCard.statusLabel}
        </span>
      </div>
      <p className="admin-agent-ramp-note">{activationCard.description}</p>
      {activationCard.releaseId ? (
        <dl className="admin-agent-uex-meta">
          <div>
            <dt>Registered release</dt>
            <dd><code>{activationCard.releaseId}</code></dd>
          </div>
          <div>
            <dt>Next action</dt>
            <dd>{activationCard.nextHumanAction}</dd>
          </div>
        </dl>
      ) : null}

      {activationCard.canCreateRequest ? (
        <>
          <div className="admin-agent-ramp-fields">
            <label>
              <span>Audit reason</span>
              <textarea
                value={auditReason}
                onChange={(event) => setAuditReason(event.target.value)}
                rows={2}
                maxLength={320}
                placeholder="Why should this verified source release become active now?"
                disabled={pending}
              />
            </label>
            <label>
              <span>Confirm action</span>
              <select
                value={confirmedState}
                onChange={(event) => setConfirmedState(event.target.value)}
                disabled={pending}
              >
                <option value="">Select confirmation</option>
                <option value={confirmationState}>Request activation</option>
              </select>
            </label>
          </div>
          <div className="admin-action-row admin-agent-ramp-actions">
            <button
              type="button"
              className="admin-command admin-command-primary admin-stateful-command"
              data-state={pending ? "busy" : disabledReason ? "unavailable" : "ready"}
              onClick={() => void submitRequest()}
              disabled={Boolean(disabledReason) || pending}
              title={disabledReason ?? undefined}
            >
              {pending ? "Recording activation request..." : "Request snapshot activation"}
            </button>
            {disabledReason ? (
              <p className="admin-action-status" data-state="unavailable">
                Request unavailable: {disabledReason}
              </p>
            ) : null}
          </div>
          <p className="admin-agent-uex-command-note">
            This records a control-plane request only. A trusted worker verifies the stored artifact,
            activates the release, and refreshes queue supply later.
          </p>
        </>
      ) : null}
      <DecisionView decision={decision} />
    </section>
  );
}

function activationDisabledReason(input: {
  context: ActivationContext;
  activationCard: SnapshotActivationCardPresentation;
  stepUpFresh: boolean;
  auditReason: string;
  confirmedState: string;
}): string | undefined {
  if (input.context.source !== "live") return "Live control-plane data is required.";
  if (input.context.role !== "admin") return "Activation requests require the admin role.";
  if (input.context.assuranceLevel !== "aal2") return "Activation requests require verified MFA.";
  if (!input.stepUpFresh) return "Verify MFA again before requesting activation.";
  if (!input.activationCard.canCreateRequest) return input.activationCard.nextHumanAction;
  if (!input.auditReason.trim()) return "Audit reason is required.";
  if (input.confirmedState !== confirmationState) return "Select Request activation to confirm.";
  return undefined;
}

function DecisionView({ decision }: { decision: Decision }) {
  if (decision.state === "idle" || decision.state === "running") return null;
  if (decision.state === "requested") {
    return (
      <div className="admin-command-result admin-command-result-ok" role="status">
        <strong>Activation request recorded</strong>
        <span>Request {decision.requestId} · release {decision.releaseId} · audit {decision.auditId}</span>
      </div>
    );
  }
  if (decision.state === "blocked") {
    return (
      <div className="admin-command-result admin-command-result-error" role="alert">
        <strong>Activation request blocked</strong>
        <span>{decision.blocks.map((block) => blockLabels[block] ?? block).join(" ")}</span>
      </div>
    );
  }
  return (
    <div className="admin-command-result admin-command-result-error" role="alert">
      <strong>Activation request failed</strong>
      <span>{decision.message}</span>
    </div>
  );
}
