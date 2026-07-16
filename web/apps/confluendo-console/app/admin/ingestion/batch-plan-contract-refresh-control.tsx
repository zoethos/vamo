"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import type { AdminAssuranceLevel, AdminRole } from "@confluendo/ingestion-platform/admin-auth";
import {
  PLAN_CONTRACT_REFRESH_CONFIRMATION_STATE,
  type BatchPlanContractRefreshCardPresentation
} from "@confluendo/ingestion-platform/core/batch-plan-contract-refresh";

type DashboardSource = "live" | "sample" | "error";

type RefreshContext = {
  role: AdminRole;
  assuranceLevel: AdminAssuranceLevel;
  source: DashboardSource;
};

type Decision =
  | { state: "idle" }
  | { state: "running" }
  | { state: "completed"; changed: boolean; auditId?: string }
  | { state: "blocked"; blocks: string[] }
  | { state: "error"; message: string };

const freshStepUpHref =
  "/admin/mfa/challenge?reason=fresh_step_up_required&next=%2Fadmin%2Fingestion";

const blockLabels: Record<string, string> = {
  missing_audit_reason: "Audit reason is required.",
  missing_actor_identity: "An authenticated operator identity is required.",
  actor_not_admin: "Plan contract refresh requires the admin role.",
  fresh_step_up_required: "Plan contract refresh requires a fresh MFA check.",
  mapping_already_configured: "This plan already has a source mapping and will not be overwritten.",
  published_contract_unavailable: "No published source mapping is available for this active plan."
};

export function BatchPlanContractRefreshControl({
  projectKey,
  card,
  context,
  freshStepUpExpiresAt,
  serverNowMs
}: {
  projectKey: string;
  card: BatchPlanContractRefreshCardPresentation;
  context: RefreshContext;
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
  const disabledReason =
    refreshDisabledReason(context, card, stepUpFresh) ??
    (!auditReason.trim() ? "Audit reason is required." : undefined) ??
    (confirmedState !== PLAN_CONTRACT_REFRESH_CONFIRMATION_STATE
      ? "Select refresh published contract to confirm."
      : undefined);

  async function submitRefresh() {
    if (inFlightRef.current) return;
    if (disabledReason) {
      setDecision({ state: "error", message: disabledReason });
      return;
    }
    inFlightRef.current = true;
    setDecision({ state: "running" });
    try {
      const response = await fetch("/api/admin/ingestion/batch-plan/source-taxonomy/refresh", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          projectKey,
          auditReason: auditReason.trim(),
          confirmedState: PLAN_CONTRACT_REFRESH_CONFIRMATION_STATE
        })
      });
      const payload = (await response.json().catch(() => null)) as
        | { ok: true; changed: boolean; auditId?: string }
        | { ok: false; decision?: "blocked"; blocks?: Array<{ code: string }>; error?: string }
        | null;
      if (!payload) {
        setDecision({ state: "error", message: "The plan contract refresh did not return a response." });
        return;
      }
      if (payload.ok) {
        setDecision({ state: "completed", changed: payload.changed, auditId: payload.auditId });
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
      setDecision({ state: "error", message: payload.error ?? "The plan contract refresh was refused." });
    } catch {
      setDecision({ state: "error", message: "The plan contract refresh failed to send." });
    } finally {
      inFlightRef.current = false;
    }
  }

  return (
    <section
      className={`admin-agent-uex-panel admin-agent-handoff-panel admin-agent-handoff-${card.tone}`}
      aria-labelledby="plan-contract-refresh-heading"
    >
      <div className="admin-agent-uex-panel-header">
        <h3 id="plan-contract-refresh-heading">{card.title}</h3>
        <span className={`admin-delivery-state admin-delivery-state-${card.tone}`}>
          {card.statusLabel}
        </span>
      </div>
      <p className="admin-agent-ramp-note">{card.description}</p>
      {card.mappingSummary ? <p className="admin-agent-uex-runbook-note">{card.mappingSummary}</p> : null}
      <ul className="admin-agent-uex-guardrails">
        {card.safeguards.map((safeguard) => (
          <li key={safeguard}>{safeguard}</li>
        ))}
      </ul>

      {card.canRefresh ? (
        <>
          <div className="admin-agent-ramp-fields">
            <label>
              <span>Audit reason</span>
              <textarea
                value={auditReason}
                onChange={(event) => setAuditReason(event.target.value)}
                rows={2}
                maxLength={320}
                placeholder="Why should the published source mapping be added to this active plan now?"
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
                <option value={PLAN_CONTRACT_REFRESH_CONFIRMATION_STATE}>
                  Refresh published contract
                </option>
              </select>
            </label>
          </div>
          <div className="admin-action-row admin-agent-ramp-actions">
            <button
              type="button"
              className="admin-command admin-command-primary admin-stateful-command"
              data-state={pending ? "busy" : disabledReason ? "unavailable" : "ready"}
              onClick={() => void submitRefresh()}
              disabled={Boolean(disabledReason) || pending}
              title={disabledReason ?? undefined}
            >
              {pending ? "Recording plan contract refresh..." : "Refresh published plan contract"}
            </button>
            {disabledReason ? (
              <p className="admin-action-status" data-state="unavailable">
                Refresh unavailable: {disabledReason}
              </p>
            ) : null}
          </div>
        </>
      ) : null}
      <DecisionView decision={decision} />
    </section>
  );
}

function refreshDisabledReason(
  context: RefreshContext,
  card: BatchPlanContractRefreshCardPresentation,
  stepUpFresh: boolean
): string | undefined {
  if (context.source !== "live") return "Plan contract refresh requires a live control plane.";
  if (!card.canRefresh) return "No plan contract refresh is currently required.";
  if (context.role !== "admin") return "Plan contract refresh requires the admin role.";
  if (context.assuranceLevel !== "aal2") return "Plan contract refresh requires verified MFA.";
  if (!stepUpFresh) return "Refresh MFA before changing plan contract metadata.";
  return undefined;
}

function DecisionView({ decision }: { decision: Decision }) {
  if (decision.state === "idle" || decision.state === "running") return null;
  if (decision.state === "completed") {
    return (
      <div className="admin-command-result admin-command-result-ok" role="status">
        <strong>{decision.changed ? "Plan contract refreshed" : "Plan contract already configured"}</strong>
        <span>
          {decision.changed
            ? `Source mapping recorded${decision.auditId ? ` · audit id ${decision.auditId}` : ""}.`
            : "No queue or evidence records were changed."}
        </span>
      </div>
    );
  }
  if (decision.state === "blocked") {
    return (
      <div className="admin-command-result admin-command-result-error" role="alert">
        <strong>Plan contract refresh blocked</strong>
        {decision.blocks.map((block) => (
          <span key={block}>{blockLabels[block] ?? block}</span>
        ))}
      </div>
    );
  }
  return (
    <div className="admin-command-result admin-command-result-error" role="alert">
      <strong>Plan contract refresh failed</strong>
      <span>{decision.message}</span>
    </div>
  );
}
