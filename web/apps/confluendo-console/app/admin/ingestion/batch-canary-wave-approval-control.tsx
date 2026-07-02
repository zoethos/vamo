"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import type { AdminAssuranceLevel, AdminRole } from "@confluendo/ingestion-platform/admin-auth";

type DashboardSource = "live" | "sample" | "error";

type BatchCanaryWaveContext = {
  role: AdminRole;
  assuranceLevel: AdminAssuranceLevel;
  source: DashboardSource;
};

type WavePlan = {
  targetEnvironment: string;
  maxUnits: number;
  maxRows: number;
  unitKeys: string[];
  totalPlannedRows: number;
  approvalExpiresAt: string;
};

type Decision =
  | { state: "idle" }
  | { state: "running" }
  | {
      state: "approved";
      auditId: string | null;
      waveKey: string;
      idempotentReplay: boolean;
      plan: WavePlan;
    }
  | { state: "blocked"; blocks: string[] }
  | { state: "error"; message: string; code?: string };

const blockLabels: Record<string, string> = {
  role_denied: "Requires the ingestion_admin role (admin).",
  scope_denied: "This admin account is not scoped to this ingestion project.",
  mfa_required: "Requires verified MFA step-up (AAL2).",
  fresh_step_up_required: "Requires a fresh MFA step-up.",
  audit_reason_required: "A non-empty audit reason is required.",
  production_environment_forbidden: "Production is forbidden for batch staging-canary waves.",
  target_environment_required: "An explicit target environment is required.",
  target_environment_mismatch: "Target environment must be staging.",
  target_key_mismatch: "Target key must match the active batch plan.",
  max_units_invalid: "maxUnits must be a positive integer.",
  max_rows_invalid: "maxRows must be a positive integer.",
  unsafe_safety_mode: "Only dry-run batch plans can approve staging-canary waves.",
  dry_run_report_missing: "A dry_run_succeeded unit is missing its dry-run report.",
  dry_run_invariant_violated: "Dry-run report must have wroteToTarget=false.",
  unit_row_bound_exceeded: "A unit exceeds the per-unit staging-canary row bound.",
  wave_row_bound_exceeded: "Selected units exceed the wave maxRows bound.",
  no_eligible_items: "No dry_run_succeeded units with valid dry-run reports are available."
};

const freshStepUpHref =
  "/admin/mfa/challenge?reason=fresh_step_up_required&next=%2Fadmin%2Fingestion";

export function BatchCanaryWaveApprovalControl({
  projectKey,
  targetKey,
  targetEnvironment,
  eligibleCount,
  context
}: {
  projectKey: string;
  targetKey: string;
  targetEnvironment: string;
  eligibleCount: number;
  context: BatchCanaryWaveContext;
}) {
  const [reason, setReason] = useState("");
  const [maxUnits, setMaxUnits] = useState("1");
  const [maxRows, setMaxRows] = useState("50");
  const [decision, setDecision] = useState<Decision>({ state: "idle" });
  const inFlightRef = useRef(false);
  const router = useRouter();
  const pending = decision.state === "running";
  const disabledReason = disabledReasonFor(context, eligibleCount);

  if (eligibleCount === 0) {
    return null;
  }

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
      const response = await fetch("/api/admin/ingestion/batch-canary-wave/approve", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          projectKey,
          targetKey,
          targetEnvironment,
          maxUnits: Number.parseInt(maxUnits, 10),
          maxRows: Number.parseInt(maxRows, 10),
          auditReason: reason.trim()
        })
      });
      const payload = (await response.json().catch(() => null)) as
        | {
            ok: true;
            decision: "approved";
            auditId: string | null;
            waveKey: string;
            idempotentReplay: boolean;
            plan: WavePlan;
          }
        | { ok: false; decision?: "blocked"; blocks?: { code: string }[]; error?: string; code?: string }
        | null;

      if (!payload) {
        setDecision({ state: "error", message: "The approval request failed." });
        return;
      }
      if (payload.ok) {
        setDecision({
          state: "approved",
          auditId: payload.auditId,
          waveKey: payload.waveKey,
          idempotentReplay: payload.idempotentReplay,
          plan: payload.plan
        });
        router.refresh();
        return;
      }
      if (payload.decision === "blocked" && Array.isArray(payload.blocks)) {
        const blocks = payload.blocks.map((block) => block.code);
        if (blocks.includes("mfa_required") || blocks.includes("fresh_step_up_required")) {
          window.location.assign(freshStepUpHref);
          return;
        }
        setDecision({ state: "blocked", blocks });
        return;
      }
      setDecision({
        state: "error",
        message: payload.error ?? "The approval request was refused.",
        code: payload.code
      });
    } catch {
      setDecision({ state: "error", message: "The approval request failed to send." });
    } finally {
      inFlightRef.current = false;
    }
  }

  return (
    <div className="admin-canary-control admin-batch-wave-approval-control">
      <p className="admin-kicker">IP-18.5 · staging-canary wave approval</p>
      <h3>Approve bounded staging-canary wave</h3>
      <p className="admin-canary-note">
        Records a control-plane wave approval for dry_run_succeeded units. Requires admin +
        verified AAL2 + fresh MFA step-up. This does not write to Vamo staging — live execution
        is a separate confirmation-gated step in a later slice.
      </p>
      <div className="admin-canary-fields">
        <label>
          <span>Target</span>
          <input type="text" value={targetKey} readOnly disabled />
        </label>
        <label>
          <span>Target environment</span>
          <input type="text" value={targetEnvironment} readOnly disabled />
        </label>
        <label>
          <span>Eligible dry_run_succeeded units</span>
          <input type="text" value={String(eligibleCount)} readOnly disabled />
        </label>
        <label>
          <span>Max units (first wave: 1 recommended)</span>
          <input
            type="number"
            min={1}
            value={maxUnits}
            onChange={(event) => setMaxUnits(event.target.value)}
            disabled={Boolean(disabledReason) || pending}
          />
        </label>
        <label>
          <span>Max rows</span>
          <input
            type="number"
            min={1}
            value={maxRows}
            onChange={(event) => setMaxRows(event.target.value)}
            disabled={Boolean(disabledReason) || pending}
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
          placeholder="Why approve this bounded staging-canary wave now?"
          disabled={Boolean(disabledReason) || pending}
        />
      </label>
      <button
        type="button"
        className="admin-command admin-command-primary"
        onClick={() => void submit()}
        disabled={Boolean(disabledReason) || pending}
        title={disabledReason ?? undefined}
      >
        {pending ? "Recording approval..." : "Approve staging-canary wave"}
      </button>
      {disabledReason ? <p className="admin-canary-disabled">{disabledReason}</p> : null}
      <DecisionView decision={decision} />
    </div>
  );
}

function DecisionView({ decision }: { decision: Decision }) {
  if (decision.state === "idle" || decision.state === "running") {
    return null;
  }
  if (decision.state === "approved") {
    return (
      <div className="admin-command-result admin-command-result-ok" role="status">
        <strong>Staging-canary wave approved (control plane only)</strong>
        <span>
          {decision.plan.unitKeys.length} unit(s) · {decision.plan.totalPlannedRows} planned rows ·{" "}
          {decision.plan.targetEnvironment}
        </span>
        <span>Wave key: {decision.waveKey}</span>
        {decision.auditId ? <span>Audit id: {decision.auditId}</span> : null}
        {decision.idempotentReplay ? <span>Idempotent replay — no duplicate wave created.</span> : null}
        <span>
          Approval expires: {new Date(decision.plan.approvalExpiresAt).toLocaleString()} · live
          staging execution remains confirmation-gated.
        </span>
      </div>
    );
  }
  if (decision.state === "blocked") {
    return (
      <div className="admin-command-result admin-command-result-error" role="alert">
        <strong>Wave approval blocked</strong>
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

function disabledReasonFor(context: BatchCanaryWaveContext, eligibleCount: number): string | undefined {
  if (context.source === "error") {
    return "Live batch queue read failed; wave approval is disabled.";
  }
  if (context.source !== "live") {
    return "Staging-canary wave approval requires a live control plane.";
  }
  if (eligibleCount === 0) {
    return "No dry_run_succeeded units with valid dry-run reports are available.";
  }
  if (context.role !== "admin") {
    return "Staging-canary wave approval requires the admin role.";
  }
  if (context.assuranceLevel !== "aal2") {
    return "Staging-canary wave approval requires verified MFA step-up (AAL2).";
  }
  return undefined;
}
