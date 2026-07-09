"use client";

import { useRef, useState } from "react";
import type { AdminAssuranceLevel, AdminRole } from "@confluendo/ingestion-platform/admin-auth";
import type {
  CanaryShipmentState,
  ProductionInboxState
} from "@confluendo/ingestion-platform/progressive-read-model";

type DashboardSource = "live" | "sample" | "error";

type ProductionInboxContext = {
  role: AdminRole;
  assuranceLevel: AdminAssuranceLevel;
  source: DashboardSource;
};

type Bounds = { maxRows: number; geography: string; category: string };

type PlanSummary = {
  targetEnvironment: "production";
  shipmentMode: "approved_write";
  schemaContract: string;
  write: { insert: number; update: number; noOp: number; writeCount: number };
  bounds: Bounds;
  approvedBy: { email: string; role: string; assuranceLevel: string };
};

type Decision =
  | { state: "idle" }
  | { state: "running" }
  | { state: "approved"; auditId: string; plan: PlanSummary }
  | { state: "blocked"; blocks: string[] }
  | { state: "error"; message: string };

const freshStepUpHref =
  "/admin/mfa/challenge?reason=fresh_step_up_required&next=%2Fadmin%2Fingestion";

const blockLabels: Record<string, string> = {
  invalid_transition: "Production inbox delivery must use the approved transition.",
  not_production_environment: "Target environment must resolve to production.",
  run_not_reviewed: "The dry run has not reached review.",
  diff_incompatible: "The reviewed shipment diff is incompatible.",
  dry_run_invariant_violated: "Simulation invariant violated (a prior write was claimed).",
  staging_canary_required: "A succeeded staging verification is required first.",
  staging_canary_not_succeeded: "The staging verification has not succeeded.",
  role_denied: "Requires the ingestion_admin role.",
  scope_denied: "Principal is not scoped to this project.",
  mfa_required: "A verified AAL2 MFA factor is required.",
  fresh_step_up_required: "A fresh MFA step-up is required.",
  audit_reason_required: "A non-empty audit reason is required.",
  delete_not_allowed: "Production inbox packages must not include deletes.",
  scope_not_narrow: "Declare exactly one narrow geography and category.",
  row_bound_exceeded: "The write count exceeds the reviewed bound.",
  nothing_to_deliver: "The reviewed diff has nothing to deliver."
};

export function ProductionInboxControl({
  targetId,
  bounds,
  canaryShipment,
  productionInbox,
  context
}: {
  targetId: string;
  bounds?: Bounds;
  canaryShipment?: CanaryShipmentState;
  productionInbox?: ProductionInboxState;
  context: ProductionInboxContext;
}) {
  const [reason, setReason] = useState("");
  const [decision, setDecision] = useState<Decision>({ state: "idle" });
  const inFlightRef = useRef(false);
  const pending = decision.state === "running";
  const disabledReason = disabledReasonFor(context, bounds, canaryShipment, productionInbox);

  async function submit() {
    if (inFlightRef.current) {
      return;
    }
    if (!reason.trim()) {
      setDecision({ state: "error", message: "Audit reason is required." });
      return;
    }
    inFlightRef.current = true;
    setDecision({ state: "running" });
    try {
      const response = await fetch("/api/admin/ingestion/production-inbox", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          projectKey: "vamo",
          targetId,
          auditReason: reason.trim()
        })
      });
      const payload = (await response.json().catch(() => null)) as
        | { ok: true; decision: "approved"; auditId: string; plan: PlanSummary }
        | { ok: false; decision?: "blocked"; blocks?: { code: string }[]; error?: string }
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
      setDecision({ state: "error", message: payload.error ?? "The production inbox approval was refused." });
    } catch {
      setDecision({ state: "error", message: "The approval request failed to send." });
    } finally {
      inFlightRef.current = false;
    }
  }

  return (
    <div className="admin-canary-control">
      <p className="admin-kicker">IP-17 · production inbox</p>
      <h3>Deliver {targetId} to Vamo production inbox</h3>
      <p className="admin-canary-note">
        This records the approval for Confluendo to deliver a package into Vamo&apos;s
        <code> confluendo_inbox</code>. It does not apply rows to Vamo product tables;
        Vamo performs that apply step separately.
      </p>

      {productionInbox ? <ProductionInboxNotice productionInbox={productionInbox} /> : null}

      <div className="admin-canary-fields">
        <label>
          <span>Geography</span>
          <input type="text" value={bounds?.geography ?? ""} readOnly disabled placeholder="Unavailable" />
        </label>
        <label>
          <span>Category</span>
          <input type="text" value={bounds?.category ?? ""} readOnly disabled placeholder="Unavailable" />
        </label>
        <label>
          <span>Reviewed writes</span>
          <input type="text" value={bounds ? String(bounds.maxRows) : ""} readOnly disabled placeholder="Unavailable" />
        </label>
      </div>
      <label className="admin-canary-reason">
        <span>Audit reason</span>
        <textarea
          value={reason}
          onChange={(event) => setReason(event.target.value)}
          rows={2}
          maxLength={280}
          placeholder="Why should this package be delivered to the production inbox now?"
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
        {pending ? "Evaluating…" : "Request production-inbox approval"}
      </button>
      {disabledReason ? <p className="admin-canary-disabled">{disabledReason}</p> : null}
      <DecisionView decision={decision} />
    </div>
  );
}

function ProductionInboxNotice({ productionInbox }: { productionInbox: ProductionInboxState }) {
  const failed = productionInbox.status === "consumer_apply_failed";
  return (
    <div
      className={
        failed
          ? "admin-command-result admin-command-result-error"
          : "admin-command-result admin-command-result-ok"
      }
      role={failed ? "alert" : "status"}
    >
      <strong>
        {productionInbox.status === "consumer_applied"
          ? "Vamo applied this production package"
          : failed
            ? "Previous production inbox delivery failed"
          : "Already delivered to Vamo production inbox"}
      </strong>
      <span>Shipment key: {productionInbox.shipmentKey}</span>
      {productionInbox.packageId ? <span>Package id: {productionInbox.packageId}</span> : null}
      {productionInbox.approvalAuditId ? <span>Approval audit id: {productionInbox.approvalAuditId}</span> : null}
      <span>Status: {productionInbox.status}</span>
    </div>
  );
}

function DecisionView({ decision }: { decision: Decision }) {
  if (decision.state === "idle" || decision.state === "running") {
    return null;
  }
  if (decision.state === "approved") {
    const { auditId, plan } = decision;
    return (
      <div className="admin-command-result admin-command-result-ok" role="status">
        <strong>Approved · production inbox package</strong>
        <span>
          {plan.write.insert} insert / {plan.write.update} update / {plan.write.noOp} no-op ·{" "}
          {plan.write.writeCount} write(s), bound {plan.bounds.maxRows}
        </span>
        <span>
          {plan.targetEnvironment} · {plan.schemaContract} · approved by {plan.approvedBy.email} (
          {plan.approvedBy.role}/{plan.approvedBy.assuranceLevel})
        </span>
        <span>Approval audit id: {auditId}</span>
        <span>Run the confirmation-gated IP-17 runbook with this audit id to deliver to the inbox.</span>
      </div>
    );
  }
  if (decision.state === "blocked") {
    return (
      <div className="admin-command-result admin-command-result-error" role="alert">
        <strong>Production inbox approval blocked</strong>
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
  context: ProductionInboxContext,
  bounds?: Bounds,
  canaryShipment?: CanaryShipmentState,
  productionInbox?: ProductionInboxState
): string | undefined {
  if (productionInbox?.status === "production_inbox_delivered" || productionInbox?.status === "consumer_apply_pending") {
    return "Already delivered to Vamo production inbox; Vamo apply is pending.";
  }
  if (productionInbox?.status === "consumer_applied") {
    return "Vamo has already applied this production inbox package.";
  }
  if (context.source !== "live") {
    return context.source === "error"
      ? "Live progressive read failed; production inbox approval is disabled."
      : "Production inbox approval requires a live control plane.";
  }
  if (!bounds) {
    return "Reviewed bounds are missing from the control plane.";
  }
  if (canaryShipment?.status !== "succeeded") {
    return "A succeeded Vamo staging verification is required first.";
  }
  if (context.role !== "admin") {
    return "Production inbox delivery requires the admin role.";
  }
  if (context.assuranceLevel !== "aal2") {
    return "Production inbox delivery requires MFA step-up (AAL2).";
  }
  return undefined;
}
