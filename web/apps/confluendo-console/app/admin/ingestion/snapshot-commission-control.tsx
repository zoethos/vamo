"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import type { AdminAssuranceLevel, AdminRole } from "@confluendo/ingestion-platform/admin-auth";
import type { SnapshotCommissionCardPresentation } from "@confluendo/ingestion-platform/core";

/** Must stay aligned with SNAPSHOT_COMMISSION_CONFIRMATION_STATE in core. */
const SNAPSHOT_COMMISSION_CONFIRMATION_STATE = "request_commission" as const;

type DashboardSource = "live" | "sample" | "error";

type CommissionContext = {
  role: AdminRole;
  assuranceLevel: AdminAssuranceLevel;
  source: DashboardSource;
};

type Decision =
  | { state: "idle" }
  | { state: "running" }
  | {
      state: "requested";
      requestId: string;
      auditId: string;
      status: string;
    }
  | { state: "blocked"; blocks: string[] }
  | { state: "error"; message: string; code?: string };

const blockLabels: Record<string, string> = {
  missing_audit_reason: "Audit reason is required.",
  missing_actor_identity: "An authenticated operator identity is required.",
  actor_not_admin: "Commissioning requests require the admin role.",
  fresh_step_up_required: "Commissioning requests require a fresh MFA check.",
  commission_request_already_active: "An active commissioning request already exists for this plan.",
  confirmed_state_mismatch: "Confirmation state must match the commissioning token.",
  scope_out_of_bounds: "Selected scope is outside approved FSQ bounds."
};

const freshStepUpHref =
  "/admin/mfa/challenge?reason=fresh_step_up_required&next=%2Fadmin%2Fingestion";

export function SnapshotCommissionControl({
  projectKey,
  planKey,
  sourceKey,
  commissionCard,
  defaultCountries,
  defaultCategories,
  defaultMaxRowsPerScope,
  context,
  freshStepUpExpiresAt,
  serverNowMs
}: {
  projectKey: string;
  planKey: string;
  sourceKey: string;
  commissionCard: SnapshotCommissionCardPresentation;
  defaultCountries: string[];
  defaultCategories: string[];
  defaultMaxRowsPerScope: number;
  context: CommissionContext;
  freshStepUpExpiresAt?: string;
  serverNowMs: number;
}) {
  const [auditReason, setAuditReason] = useState("");
  const [confirmedState, setConfirmedState] = useState("");
  const [countries, setCountries] = useState<string[]>(() => [...defaultCountries]);
  const [categories, setCategories] = useState<string[]>(() => [...defaultCategories]);
  const [maxRowsPerScope, setMaxRowsPerScope] = useState(defaultMaxRowsPerScope);
  const [decision, setDecision] = useState<Decision>({ state: "idle" });
  const inFlightRef = useRef(false);
  const router = useRouter();

  const pending = decision.state === "running";
  const stepUpFresh =
    freshStepUpExpiresAt !== undefined && Date.parse(freshStepUpExpiresAt) > serverNowMs;
  const disabledReason =
    commissionDisabledReason(context, commissionCard, stepUpFresh) ??
    (!commissionCard.canCreateRequest
      ? "An active commissioning request already exists for this batch plan."
      : undefined) ??
    (countries.length === 0 ? "Select at least one country." : undefined) ??
    (categories.length === 0 ? "Select at least one category." : undefined) ??
    (!auditReason.trim() ? "Audit reason is required." : undefined) ??
    (confirmedState !== SNAPSHOT_COMMISSION_CONFIRMATION_STATE
      ? "Select request commissioning in the confirmation dropdown."
      : undefined);

  async function submitRequest() {
    if (inFlightRef.current) {
      return;
    }
    if (!auditReason.trim()) {
      setDecision({ state: "error", message: "Audit reason is required." });
      return;
    }
    if (confirmedState !== SNAPSHOT_COMMISSION_CONFIRMATION_STATE) {
      setDecision({ state: "error", message: "Select request commissioning to confirm." });
      return;
    }
    if (countries.length === 0 || categories.length === 0) {
      setDecision({ state: "error", message: "Select at least one country and category." });
      return;
    }

    inFlightRef.current = true;
    setDecision({ state: "running" });

    try {
      const response = await fetch("/api/admin/ingestion/snapshot-commission/request", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          projectKey,
          planKey,
          countries,
          categories,
          maxRowsPerScope,
          auditReason: auditReason.trim(),
          confirmedState: SNAPSHOT_COMMISSION_CONFIRMATION_STATE
        })
      });
      const payload = (await response.json().catch(() => null)) as
        | {
            ok: true;
            requestId: string;
            auditId: string;
            status: string;
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
        setDecision({ state: "error", message: "The commissioning request failed." });
        return;
      }

      if (payload.ok) {
        setDecision({
          state: "requested",
          requestId: payload.requestId,
          auditId: payload.auditId,
          status: payload.status
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
        message: payload.error ?? "The commissioning request was refused.",
        code: payload.code
      });
    } catch {
      setDecision({ state: "error", message: "The commissioning request failed to send." });
    } finally {
      inFlightRef.current = false;
    }
  }

  return (
    <section
      className={`admin-agent-uex-panel admin-agent-handoff-panel admin-agent-handoff-${commissionCard.tone}`}
      aria-labelledby="snapshot-commission-heading"
    >
      <div className="admin-agent-uex-panel-header">
        <h3 id="snapshot-commission-heading">{commissionCard.title}</h3>
        <span className={`admin-delivery-state admin-delivery-state-${commissionCard.tone}`}>
          {commissionCard.statusLabel}
        </span>
      </div>

      <p className="admin-agent-ramp-note">{commissionCard.description}</p>

      <dl className="admin-agent-uex-meta">
        <div>
          <dt>Bounded scope</dt>
          <dd>{commissionCard.scopeSummary}</dd>
        </div>
        <div>
          <dt>Next human action</dt>
          <dd>{commissionCard.nextHumanAction}</dd>
        </div>
        {commissionCard.registeredReleaseId ? (
          <div>
            <dt>Registered release</dt>
            <dd>{commissionCard.registeredReleaseId}</dd>
          </div>
        ) : null}
        {commissionCard.requestedAt ? (
          <div>
            <dt>Requested</dt>
            <dd>
              {new Date(commissionCard.requestedAt).toLocaleString()}
              {commissionCard.requestedById ? ` · ${commissionCard.requestedById}` : ""}
            </dd>
          </div>
        ) : null}
      </dl>

      {commissionCard.errorCode || commissionCard.errorMessage ? (
        <div className="admin-command-result admin-command-result-error" role="alert">
          <strong>Commissioning error: {commissionCard.errorCode ?? "failed"}</strong>
          <span>{commissionCard.errorMessage ?? "Review worker logs and submit a new request."}</span>
        </div>
      ) : null}

      {commissionCard.recoveryHint ? (
        <p className="admin-agent-uex-runbook-note">{commissionCard.recoveryHint}</p>
      ) : null}

      {commissionCard.canCreateRequest ? (
        <>
          <div className="admin-agent-ramp-fields">
            <fieldset className="admin-agent-commission-scope">
              <legend>Countries</legend>
              <div className="admin-agent-commission-options">
                {defaultCountries.map((country) => (
                  <label key={country}>
                    <input
                      type="checkbox"
                      checked={countries.includes(country)}
                      onChange={(event) =>
                        setCountries((current) =>
                          event.target.checked
                            ? [...current, country].sort()
                            : current.filter((entry) => entry !== country)
                        )
                      }
                      disabled={pending}
                    />
                    <span>{country}</span>
                  </label>
                ))}
              </div>
            </fieldset>
            <fieldset className="admin-agent-commission-scope">
              <legend>Categories</legend>
              <div className="admin-agent-commission-options">
                {defaultCategories.map((category) => (
                  <label key={category}>
                    <input
                      type="checkbox"
                      checked={categories.includes(category)}
                      onChange={(event) =>
                        setCategories((current) =>
                          event.target.checked
                            ? [...current, category].sort()
                            : current.filter((entry) => entry !== category)
                        )
                      }
                      disabled={pending}
                    />
                    <span>{category}</span>
                  </label>
                ))}
              </div>
            </fieldset>
            <label>
              <span>Max rows per scope</span>
              <input
                type="number"
                min={1}
                max={250}
                value={maxRowsPerScope}
                onChange={(event) => setMaxRowsPerScope(Number.parseInt(event.target.value, 10) || 1)}
                disabled={pending}
              />
            </label>
            <label>
              <span>Audit reason</span>
              <textarea
                value={auditReason}
                onChange={(event) => setAuditReason(event.target.value)}
                rows={2}
                maxLength={320}
                placeholder="Why should a trusted worker acquire a bounded FSQ snapshot release now?"
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
                <option value={SNAPSHOT_COMMISSION_CONFIRMATION_STATE}>Request commissioning</option>
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
              {pending ? "Submitting commissioning request..." : "Request commissioning"}
            </button>
            {disabledReason ? (
              <p className="admin-action-status" data-state="unavailable">
                Request unavailable: {disabledReason}
              </p>
            ) : null}
          </div>

          <p className="admin-agent-uex-command-note">
            This records a control-plane request only. A trusted worker runs bounded acquisition later;
            the browser never calls the provider or accesses artifacts.
          </p>
        </>
      ) : null}

      <DecisionView decision={decision} />
    </section>
  );
}

function DecisionView({ decision }: { decision: Decision }) {
  if (decision.state === "idle" || decision.state === "running") {
    return null;
  }
  if (decision.state === "requested") {
    return (
      <div className="admin-command-result admin-command-result-ok" role="status">
        <strong>Commissioning request recorded</strong>
        <span>
          Status {decision.status} · request {decision.requestId} · audit id {decision.auditId}
        </span>
        <span>A trusted worker will run acquisition. Activation remains a separate action.</span>
      </div>
    );
  }
  if (decision.state === "blocked") {
    return (
      <div className="admin-command-result admin-command-result-error" role="alert">
        <strong>Commissioning request blocked</strong>
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

function commissionDisabledReason(
  context: CommissionContext,
  card: SnapshotCommissionCardPresentation,
  stepUpFresh: boolean
): string | undefined {
  if (context.source === "error") {
    return "Live control-plane read failed.";
  }
  if (context.source !== "live") {
    return "Commissioning requests require a live control plane.";
  }
  if (context.role !== "admin") {
    return "Commissioning requests require the admin role.";
  }
  if (context.assuranceLevel !== "aal2") {
    return "Commissioning requests require verified MFA.";
  }
  if (!stepUpFresh) {
    return "Commissioning requests require a fresh MFA step-up.";
  }
  if (!card.canCreateRequest) {
    return "An active commissioning request already exists for this batch plan.";
  }
  return undefined;
}
