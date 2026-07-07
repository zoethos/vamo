"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import type { AdminAssuranceLevel, AdminRole } from "@confluendo/ingestion-platform/admin-auth";

type DashboardSource = "live" | "sample" | "error";

type ProductionPackageWaveStatusPresentation = {
  label: string;
  tone: "neutral" | "good" | "watch" | "danger";
  detail?: string;
};

type ProductionPackageWaveContext = {
  role: AdminRole;
  assuranceLevel: AdminAssuranceLevel;
  source: DashboardSource;
};

type PackageWavePlan = {
  targetEnvironment: string;
  schemaContract: string;
  maxUnits: number;
  maxRows: number;
  maxPackages: number;
  unitKeys: string[];
  totalPlannedRows: number;
  approvalExpiresAt: string;
};

type LatestWaveSummary = {
  waveKey: string;
  status: string;
  schemaContract: string;
  approvalExpiresAt?: string;
  statusPresentation: ProductionPackageWaveStatusPresentation;
};

type PackageProgress = {
  ready: number;
  approved: number;
  delivering: number;
  delivered: number;
  applyPending: number;
  applied: number;
  applyFailed: number;
  blocked: number;
};

type Decision =
  | { state: "idle" }
  | { state: "running" }
  | {
      state: "approved";
      auditId: string;
      waveKey: string;
      idempotentReplay: boolean;
      plan: PackageWavePlan;
    }
  | { state: "blocked"; blocks: string[] }
  | { state: "error"; message: string; code?: string };

const freshStepUpHref =
  "/admin/mfa/challenge?reason=fresh_step_up_required&next=%2Fadmin%2Fingestion";

const blockLabels: Record<string, string> = {
  not_staging_proven: "Unit is not staging_canary_succeeded.",
  not_production_environment: "Package wave target environment must be production.",
  legacy_target_key: "Target key must be environment-neutral.",
  schema_contract_mismatch: "Schema contract must be vamo-place-intelligence@1.",
  dry_run_invariant_violated: "Dry-run report must have wroteToTarget=false.",
  staging_canary_required: "Staging-canary evidence is required.",
  staging_canary_not_succeeded: "Staging-canary evidence must be succeeded.",
  active_blockers: "Active blockers remain on the queue item.",
  delete_not_allowed: "Deletes are not allowed in production package waves.",
  row_bound_exceeded: "Selected rows exceed the wave maxRows bound.",
  unit_bound_exceeded: "Selected units exceed the wave maxUnits bound.",
  package_bound_exceeded: "Selected packages exceed the wave maxPackages bound.",
  already_delivered_or_pending_apply: "Unit is already in an active or spent package wave.",
  approval_expired: "Package-wave approval has expired.",
  role_denied: "Requires the ingestion_admin role (admin).",
  scope_denied: "This admin account is not scoped to this ingestion project.",
  mfa_required: "Requires verified MFA step-up (AAL2).",
  fresh_step_up_required: "Requires a fresh MFA step-up.",
  audit_reason_required: "A non-empty audit reason is required.",
  max_units_invalid: "maxUnits must be a positive integer.",
  max_rows_invalid: "maxRows must be a positive integer.",
  max_packages_invalid: "maxPackages must be a positive integer.",
  first_wave_ramp_exceeded: "The first live production package wave is hard-capped at 1 unit / 1 package.",
  no_eligible_items: "No staging-proven units with valid evidence are available."
};

export function ProductionPackageWaveApprovalControl({
  projectKey,
  targetKey,
  eligibleCount,
  packageProgress,
  latestWave,
  context
}: {
  projectKey: string;
  targetKey: string;
  eligibleCount: number;
  packageProgress: PackageProgress;
  latestWave?: LatestWaveSummary | null;
  context: ProductionPackageWaveContext;
}) {
  const [reason, setReason] = useState("");
  const [maxUnits, setMaxUnits] = useState("1");
  const [maxRows, setMaxRows] = useState("10");
  const [maxPackages, setMaxPackages] = useState("1");
  const [decision, setDecision] = useState<Decision>({ state: "idle" });
  const inFlightRef = useRef(false);
  const router = useRouter();
  const pending = decision.state === "running";
  const disabledReason = disabledReasonFor(context, eligibleCount);

  return (
    <div className="admin-canary-control admin-batch-wave-approval-control">
      <p className="admin-kicker">IP-18.6 · production package-wave approval</p>
      <h3>Approve bounded production package wave</h3>
      <p className="admin-canary-note">
        Records a control-plane package-wave approval for staging_canary_succeeded units.
        Requires admin + verified AAL2 + fresh MFA step-up. This does not deliver to the
        production inbox — delivery is a separate confirmation-gated runbook step (IP-18.6.3).
        Consumer apply remains consumer-owned.
      </p>

      <div className="admin-canary-fields">
        <label>
          <span>Target</span>
          <input type="text" value={targetKey} readOnly disabled />
        </label>
        <label>
          <span>Target environment</span>
          <input type="text" value="production" readOnly disabled />
        </label>
        <label>
          <span>Schema contract</span>
          <input type="text" value="vamo-place-intelligence@1" readOnly disabled />
        </label>
        <label>
          <span>Eligible staging-proven units</span>
          <input type="text" value={String(eligibleCount)} readOnly disabled />
        </label>
        <label>
          <span>Max units (first wave: 1)</span>
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
        <label>
          <span>Max packages (first wave: 1)</span>
          <input
            type="number"
            min={1}
            value={maxPackages}
            onChange={(event) => setMaxPackages(event.target.value)}
            disabled={Boolean(disabledReason) || pending}
          />
        </label>
      </div>

      <div className="admin-stat-grid">
        <article className="admin-stat">
          <span>Package progress</span>
          <strong>{packageProgress.approved}</strong>
          <p>
            {packageProgress.ready} ready · {packageProgress.delivered} delivered ·{" "}
            {packageProgress.applyPending} apply pending
          </p>
        </article>
        <article className="admin-stat">
          <span>Consumer apply</span>
          <strong>{packageProgress.applied}</strong>
          <p>
            {packageProgress.applyFailed} failed · {packageProgress.blocked} blocked
          </p>
        </article>
      </div>

      {latestWave ? (
        <div className="admin-command-result" role="status">
          <strong>Latest package wave: {latestWave.statusPresentation.label}</strong>
          <span>Wave key: {latestWave.waveKey}</span>
          <span>Schema: {latestWave.schemaContract}</span>
          {latestWave.approvalExpiresAt ? (
            <span>Approval expires: {new Date(latestWave.approvalExpiresAt).toLocaleString()}</span>
          ) : null}
          {latestWave.statusPresentation.detail ? <span>{latestWave.statusPresentation.detail}</span> : null}
        </div>
      ) : null}

      <label className="admin-canary-reason">
        <span>Audit reason</span>
        <textarea
          value={reason}
          onChange={(event) => setReason(event.target.value)}
          rows={2}
          maxLength={280}
          placeholder="Why approve this bounded production package wave now?"
          disabled={Boolean(disabledReason) || pending}
        />
      </label>
      <button
        type="button"
        className="admin-command admin-command-primary"
        onClick={() => void submit()}
        disabled={Boolean(disabledReason) || pending || eligibleCount === 0}
        title={disabledReason ?? undefined}
      >
        {pending ? "Recording approval..." : "Approve production package wave"}
      </button>
      {disabledReason ? <p className="admin-canary-disabled">{disabledReason}</p> : null}
      <DecisionView decision={decision} />
    </div>
  );

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
      const response = await fetch("/api/admin/ingestion/production-package-wave/approve", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          projectKey,
          targetKey,
          targetEnvironment: "production",
          schemaContract: "vamo-place-intelligence@1",
          maxUnits: Number.parseInt(maxUnits, 10),
          maxRows: Number.parseInt(maxRows, 10),
          maxPackages: Number.parseInt(maxPackages, 10),
          auditReason: reason.trim()
        })
      });
      const payload = (await response.json().catch(() => null)) as
        | {
            ok: true;
            decision: "approved";
            auditId: string;
            waveKey: string;
            idempotentReplay: boolean;
            plan: PackageWavePlan;
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
}

function DecisionView({ decision }: { decision: Decision }) {
  if (decision.state === "idle" || decision.state === "running") {
    return null;
  }
  if (decision.state === "approved") {
    return (
      <div className="admin-command-result admin-command-result-ok" role="status">
        <strong>Production package wave approved (control plane only)</strong>
        <span>
          {decision.plan.unitKeys.length} unit(s) · {decision.plan.totalPlannedRows} planned rows ·{" "}
          {decision.plan.targetEnvironment}
        </span>
        <span>Schema: {decision.plan.schemaContract}</span>
        <span>Wave key: {decision.waveKey}</span>
        <span>Audit id: {decision.auditId}</span>
        {decision.idempotentReplay ? <span>Idempotent replay — no duplicate wave created.</span> : null}
        <span>
          Approval expires: {new Date(decision.plan.approvalExpiresAt).toLocaleString()} · production
          inbox delivery remains confirmation-gated.
        </span>
      </div>
    );
  }
  if (decision.state === "blocked") {
    return (
      <div className="admin-command-result admin-command-result-error" role="alert">
        <strong>Package-wave approval blocked</strong>
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
  context: ProductionPackageWaveContext,
  eligibleCount: number
): string | undefined {
  if (context.source === "error") {
    return "Live batch queue read failed; package-wave approval is disabled.";
  }
  if (context.source !== "live") {
    return "Production package-wave approval requires a live control plane.";
  }
  if (eligibleCount === 0) {
    return "No staging_canary_succeeded units with valid dry-run and staging evidence are available.";
  }
  if (context.role !== "admin") {
    return "Production package-wave approval requires the admin role.";
  }
  if (context.assuranceLevel !== "aal2") {
    return "Production package-wave approval requires verified MFA step-up (AAL2).";
  }
  return undefined;
}
