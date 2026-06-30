"use client";

import { useRef, useState } from "react";
import type { AdminAssuranceLevel, AdminRole } from "@vamo/ingestion-platform/admin-auth";
import type { CanaryShipmentState } from "@vamo/ingestion-platform/progressive-read-model";

type DashboardSource = "live" | "sample";

type CanaryContext = {
  role: AdminRole;
  assuranceLevel: AdminAssuranceLevel;
  source: DashboardSource;
};

type CanaryBounds = { maxRows: number; geography: string; category: string };

type PlanSummary = {
  environment: string;
  safetyMode: string;
  shipmentMode: string;
  write: { insert: number; update: number; noOp: number; writeCount: number };
  bounds: CanaryBounds;
  approvedBy: { email: string; role: string; assuranceLevel: string };
};

type Decision =
  | { state: "idle" }
  | { state: "running" }
  | { state: "approved"; auditId: string; plan: PlanSummary }
  | { state: "blocked"; blocks: string[] }
  | { state: "error"; message: string };

const blockLabels: Record<string, string> = {
  invalid_transition: "Promotion must start from review_required.",
  production_write_forbidden: "Production writes are forbidden.",
  unsupported_safety_mode: "Only staging_write is promotable.",
  not_staging_environment: "Resolved target environment is not staging.",
  run_not_reviewed: "The dry run has not reached review.",
  diff_incompatible: "The reviewed shipment diff is incompatible.",
  dry_run_invariant_violated: "Dry-run invariant violated (a prior write was claimed).",
  role_denied: "Requires the ingestion_admin role.",
  scope_denied: "Principal is not scoped to this project.",
  mfa_required: "A verified AAL2 MFA factor is required.",
  fresh_step_up_required: "A fresh MFA step-up is required.",
  audit_reason_required: "A non-empty audit reason is required.",
  delete_not_allowed: "A canary must not delete rows.",
  scope_not_narrow: "Declare exactly one narrow geography and category.",
  row_bound_exceeded: "The write count exceeds the canary bound.",
  nothing_to_ship: "The reviewed diff has nothing to ship."
};

const freshStepUpHref =
  "/admin/mfa/challenge?reason=fresh_step_up_required&next=%2Fadmin%2Fingestion";

export function StagingCanaryControl({
  targetId,
  context,
  bounds,
  shipment,
  alreadyShipped = false,
}: {
  targetId: string;
  context: CanaryContext;
  bounds?: CanaryBounds;
  shipment?: CanaryShipmentState;
  alreadyShipped?: boolean;
}) {
  const [reason, setReason] = useState("");
  const [decision, setDecision] = useState<Decision>({ state: "idle" });
  const inFlightRef = useRef(false);

  const disabledReason = disabledReasonFor(context, bounds, alreadyShipped);
  const pending = decision.state === "running";

  async function submit() {
    if (inFlightRef.current || alreadyShipped) {
      return;
    }
    if (!bounds) {
      setDecision({ state: "error", message: "Reviewed canary bounds are unavailable." });
      return;
    }
    if (!reason.trim()) {
      setDecision({ state: "error", message: "Audit reason is required." });
      return;
    }
    inFlightRef.current = true;
    setDecision({ state: "running" });

    try {
      const response = await fetch("/api/admin/ingestion/staging-canary", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          projectKey: "vamo",
          targetId,
          auditReason: reason.trim()
        }),
      });
      const payload = (await response.json().catch(() => null)) as
        | { ok: true; decision: "approved"; auditId: string; plan: PlanSummary }
        | { ok: false; decision?: "blocked"; blocks?: { code: string }[]; error?: string; code?: string }
        | null;

      if (!payload) {
        setDecision({ state: "error", message: "The approval request failed." });
        return;
      }
      if (payload.ok) {
        setDecision({ state: "approved", auditId: payload.auditId, plan: payload.plan });
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
      setDecision({ state: "error", message: payload.error ?? "The promotion was refused." });
    } catch {
      setDecision({ state: "error", message: "The approval request failed to send." });
    } finally {
      inFlightRef.current = false;
    }
  }

  return (
    <div className="admin-canary-control">
      <p className="admin-kicker">IP-16 · staging canary</p>
      <h3>Promote {targetId} to a staging canary</h3>
      <p className="admin-canary-note">
        Approval is gated by an ingestion_admin with MFA/AAL2, a fresh step-up, and an audit
        reason. This records the decision only — the live staging write is a separate,
        confirmation-gated runbook step. No production writes.
      </p>

      {alreadyShipped ? <ShippedNotice shipment={shipment} /> : null}

      <div className="admin-canary-fields">
        <label>
          <span>Geography</span>
          <input
            type="text"
            value={bounds?.geography ?? ""}
            readOnly
            placeholder="Unavailable"
            disabled={true}
          />
        </label>
        <label>
          <span>Category</span>
          <input
            type="text"
            value={bounds?.category ?? ""}
            readOnly
            placeholder="Unavailable"
            disabled={true}
          />
        </label>
        <label>
          <span>Reviewed writes</span>
          <input
            type="text"
            value={bounds ? String(bounds.maxRows) : ""}
            readOnly
            placeholder="Unavailable"
            disabled={true}
          />
        </label>
      </div>
      <label className="admin-canary-reason">
        <span>Audit reason</span>
        <textarea
          value={reason}
          onChange={(event) => setReason(event.target.value)}
          rows={2}
          maxLength={280}
          placeholder="Why is this canary being promoted now?"
          disabled={Boolean(disabledReason) || pending}
        />
      </label>

      <button
        type="button"
        className="admin-command admin-command-danger"
        onClick={() => void submit()}
        disabled={Boolean(disabledReason) || pending}
        title={disabledReason ?? undefined}
      >
        {pending ? "Evaluating…" : "Request staging-canary approval"}
      </button>

      {disabledReason ? <p className="admin-canary-disabled">{disabledReason}</p> : null}

      <DecisionView decision={decision} />
    </div>
  );
}

function ShippedNotice({ shipment }: { shipment?: CanaryShipmentState }) {
  const shippedAt = formatShippedAt(shipment?.createdAt);
  return (
    <div className="admin-command-result admin-command-result-ok" role="status">
      <strong>Already shipped to Vamo staging</strong>
      {shipment ? (
        <>
          <span>Shipment key: {shipment.shipmentKey}</span>
          {shipment.approvalAuditId ? (
            <span>Approval audit id: {shipment.approvalAuditId}</span>
          ) : null}
          <span>
            Status: {shipment.status}
            {shippedAt ? ` · ${shippedAt}` : ""}
          </span>
        </>
      ) : null}
      <span>
        Approving again is disabled. Create a new proposal/run to ship this target again.
      </span>
    </div>
  );
}

function formatShippedAt(createdAt?: string): string | undefined {
  if (!createdAt) {
    return undefined;
  }
  const parsed = new Date(createdAt);
  return Number.isNaN(parsed.getTime()) ? createdAt : parsed.toISOString();
}

function DecisionView({ decision }: { decision: Decision }) {
  if (decision.state === "idle" || decision.state === "running") {
    return null;
  }

  if (decision.state === "approved") {
    const { auditId, plan } = decision;
    return (
      <div className="admin-command-result admin-command-result-ok" role="status">
        <strong>Approved · {plan.environment} canary plan</strong>
        <span>
          {plan.write.insert} insert / {plan.write.update} update / {plan.write.noOp} no-op ·{" "}
          {plan.write.writeCount} write(s), bound {plan.bounds.maxRows}
        </span>
        <span>
          {plan.safetyMode} → {plan.shipmentMode} · approved by {plan.approvedBy.email} (
          {plan.approvedBy.role}/{plan.approvedBy.assuranceLevel})
        </span>
        <span>Approval audit id: {auditId}</span>
        <span>Run the confirmation-gated runbook with this audit id to execute the live staging write.</span>
      </div>
    );
  }

  if (decision.state === "blocked") {
    return (
      <div className="admin-command-result admin-command-result-error" role="alert">
        <strong>Promotion blocked</strong>
        <ul>
          {decision.blocks.map((code) => (
            <li key={code}>{blockLabels[code] ?? code}</li>
          ))}
        </ul>
        {decision.blocks.includes("fresh_step_up_required") ? (
          <a className="admin-command admin-command-neutral admin-inline-action" href={freshStepUpHref}>
            Refresh MFA step-up
          </a>
        ) : null}
      </div>
    );
  }

  return (
    <div className="admin-command-result admin-command-result-error" role="alert">
      <strong>{decision.message}</strong>
    </div>
  );
}

function disabledReasonFor(
  context: CanaryContext,
  bounds?: CanaryBounds,
  alreadyShipped = false,
): string | undefined {
  if (alreadyShipped) {
    return "Already shipped to Vamo staging; create a new proposal/run to ship again.";
  }
  if (context.source !== "live") {
    return "Staging-canary approval requires a live control plane.";
  }
  if (!bounds) {
    return "Reviewed canary bounds are missing from the control plane.";
  }
  if (context.role !== "admin") {
    return "Staging-canary promotion requires the admin role.";
  }
  if (context.assuranceLevel !== "aal2") {
    return "Staging-canary promotion requires MFA step-up (AAL2).";
  }
  return undefined;
}
