"use client";

import { useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import type { AdminAssuranceLevel, AdminRole } from "@confluendo/ingestion-platform/admin-auth";
import type { BatchQueueItem, BatchQueueLatestWave } from "@confluendo/ingestion-platform/core";
import { extractDryRunReportMetrics } from "./ingestion-console-labels";
import { StagingWaveApprovalQueue } from "./staging-wave-approval-queue";

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

type UnitIssue = {
  unitKey: string;
  code: string;
  message: string;
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
  | { state: "blocked"; blocks: string[]; unitIssues?: UnitIssue[] }
  | { state: "error"; message: string; code?: string };

const blockLabels: Record<string, string> = {
  role_denied: "Requires the ingestion_admin role (admin).",
  scope_denied: "This admin account is not scoped to this ingestion project.",
  mfa_required: "Requires verified MFA step-up (AAL2).",
  fresh_step_up_required: "Requires a fresh MFA step-up.",
  audit_reason_required: "A non-empty audit reason is required.",
  production_environment_forbidden: "Production is forbidden for staging verification batches.",
  target_environment_required: "An explicit target environment is required.",
  target_environment_mismatch: "Target environment must be staging.",
  target_key_mismatch: "Target key must match the active batch plan.",
  max_units_invalid: "maxUnits must be a positive integer.",
  max_rows_invalid: "maxRows must be a positive integer.",
  unsafe_safety_mode: "Only simulation batch plans can approve staging verification.",
  dry_run_report_missing: "A simulation-passed scope is missing its report.",
  dry_run_invariant_violated: "Simulation report must have wroteToTarget=false.",
  unit_row_bound_exceeded: "A unit exceeds the per-unit max target writes bound.",
  wave_row_bound_exceeded: "Selected units exceed the wave max target writes bound.",
  unit_category_unsupported: "A selected source category cannot be mapped to a supported Vamo target type.",
  no_eligible_items: "No simulation-passed scopes with valid reports are available.",
  unit_key_not_found: "A selected unit is not present in the active batch queue.",
  unit_not_dry_run_succeeded: "A selected scope has not passed simulation.",
  unit_target_mismatch: "A selected unit does not match the wave target.",
  unit_selection_exceeds_max_units: "Too many units were selected for maxUnits."
};

const freshStepUpHref =
  "/admin/mfa/challenge?reason=fresh_step_up_required&next=%2Fadmin%2Fingestion";

export function BatchCanaryWaveApprovalControl({
  projectKey,
  targetKey,
  targetEnvironment,
  eligibleCount,
  queueItems,
  latestWave,
  context,
  selectedUnitKey,
  onOpenScope
}: {
  projectKey: string;
  targetKey: string;
  targetEnvironment: string;
  eligibleCount: number;
  queueItems: BatchQueueItem[];
  latestWave?: BatchQueueLatestWave | null;
  context: BatchCanaryWaveContext;
  selectedUnitKey?: string | null;
  onOpenScope?: (unitKey: string) => void;
}) {
  const [reason, setReason] = useState("");
  const [maxUnits, setMaxUnits] = useState("1");
  const [maxRows, setMaxRows] = useState("50");
  const [selectedUnitKeys, setSelectedUnitKeys] = useState<string[]>([]);
  const [decision, setDecision] = useState<Decision>({ state: "idle" });
  const inFlightRef = useRef(false);
  const router = useRouter();
  const pending = decision.state === "running";
  const disabledReason = disabledReasonFor(context, selectedUnitKeys.length);
  const selectedSummary = useMemo(() => {
    const selected = queueItems.filter((item) => selectedUnitKeys.includes(item.unitKey));
    const expectedTargetWrites = selected.reduce(
      (sum, item) => sum + expectedTargetWritesForItem(item),
      0
    );
    return { count: selected.length, expectedTargetWrites };
  }, [queueItems, selectedUnitKeys]);

  function handleSelectionChange(unitKeys: string[]) {
    setSelectedUnitKeys(unitKeys);
    if (unitKeys.length === 0) {
      setMaxUnits("1");
      setMaxRows("50");
      return;
    }
    const nextSelected = queueItems.filter((item) => unitKeys.includes(item.unitKey));
    const expectedTargetWrites = nextSelected.reduce(
      (sum, item) => sum + expectedTargetWritesForItem(item),
      0
    );
    setMaxUnits(String(unitKeys.length));
    setMaxRows(String(Math.max(1, expectedTargetWrites)));
  }

  async function submit() {
    if (inFlightRef.current) {
      return;
    }
    if (!reason.trim()) {
      setDecision({ state: "error", message: "Audit reason is required." });
      return;
    }
    if (selectedUnitKeys.length === 0) {
      setDecision({ state: "error", message: "Select at least one eligible simulation-passed scope." });
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
          auditReason: reason.trim(),
          unitKeys: selectedUnitKeys
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
        | {
            ok: false;
            decision?: "blocked";
            blocks?: { code: string }[];
            unitIssues?: UnitIssue[];
            error?: string;
            code?: string;
          }
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
        setSelectedUnitKeys([]);
        router.refresh();
        return;
      }
      if (payload.decision === "blocked" && Array.isArray(payload.blocks)) {
        const blocks = payload.blocks.map((block) => block.code);
        if (blocks.includes("mfa_required") || blocks.includes("fresh_step_up_required")) {
          window.location.assign(freshStepUpHref);
          return;
        }
        setDecision({
          state: "blocked",
          blocks,
          unitIssues: payload.unitIssues
        });
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
      <p className="admin-kicker">IP-18.5 · staging verification approval</p>
      <h3>Approve bounded staging verification</h3>
      <p className="admin-canary-note">
        Select exact simulation-passed scopes below, then approve the verification batch. Requires admin + verified
        AAL2 + fresh MFA step-up. This does not write to Vamo staging — live execution is a separate
        confirmation-gated step.
      </p>

      <StagingWaveApprovalQueue
        items={queueItems}
        latestWave={latestWave}
        onOpenScope={onOpenScope}
        onSelectionChange={handleSelectionChange}
        selectedUnitKey={selectedUnitKey}
        selectedUnitKeys={selectedUnitKeys}
      />

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
          <span>Eligible simulation-passed scopes</span>
          <input type="text" value={String(eligibleCount)} readOnly disabled />
        </label>
        <label>
          <span>Selected units</span>
          <input type="text" value={String(selectedSummary.count)} readOnly disabled />
        </label>
        <label>
          <span>Selected expected target writes</span>
          <input type="text" value={String(selectedSummary.expectedTargetWrites)} readOnly disabled />
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
          <span>Max target writes</span>
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
          placeholder="Why approve this bounded staging verification now?"
          disabled={Boolean(disabledReason) || pending}
        />
      </label>
      <div className="admin-action-row">
        <button
          type="button"
          className="admin-command admin-command-primary admin-stateful-command"
          data-state={pending ? "busy" : disabledReason ? "unavailable" : "ready"}
          onClick={() => void submit()}
          disabled={Boolean(disabledReason) || pending}
          title={disabledReason ?? undefined}
        >
          {pending ? "Recording approval..." : "Approve staging verification"}
        </button>
        {disabledReason ? (
          <p className="admin-action-status" data-state="unavailable">
            Unavailable: {disabledReason}
          </p>
        ) : null}
      </div>
      <DecisionView decision={decision} />
    </div>
  );
}

function expectedTargetWritesForItem(item: BatchQueueItem): number {
  return extractDryRunReportMetrics(item.dryRunReport)?.expectedTargetWrites ?? 0;
}

function DecisionView({ decision }: { decision: Decision }) {
  if (decision.state === "idle" || decision.state === "running") {
    return null;
  }
  if (decision.state === "approved") {
    return (
      <div className="admin-command-result admin-command-result-ok" role="status">
        <strong>Staging verification approved (control plane only)</strong>
        <span>
          {decision.plan.unitKeys.length} unit(s) · {decision.plan.totalPlannedRows} expected target
          writes · {decision.plan.targetEnvironment}
        </span>
        <span>Wave key: {decision.waveKey}</span>
        {decision.auditId ? <span>Audit id: {decision.auditId}</span> : null}
        {decision.idempotentReplay ? <span>Idempotent replay — no duplicate wave created.</span> : null}
        <span>
          Approval expires: {new Date(decision.plan.approvalExpiresAt).toLocaleString()} · live staging
          verification remains confirmation-gated.
        </span>
      </div>
    );
  }
  if (decision.state === "blocked") {
    return (
      <div className="admin-command-result admin-command-result-error" role="alert">
        <strong>Staging verification approval blocked</strong>
        <ul>
          {decision.blocks.map((code) => (
            <li key={code}>{blockLabels[code] ?? code}</li>
          ))}
        </ul>
        {decision.unitIssues && decision.unitIssues.length > 0 ? (
          <ul>
            {decision.unitIssues.map((issue) => (
              <li key={issue.unitKey}>
                <code>{issue.unitKey}</code>: {issue.message}
              </li>
            ))}
          </ul>
        ) : null}
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

function disabledReasonFor(context: BatchCanaryWaveContext, selectedCount: number): string | undefined {
  if (context.source === "error") {
    return "Live batch queue read failed; staging verification approval is disabled.";
  }
  if (context.source !== "live") {
    return "Staging verification approval requires a live control plane.";
  }
  if (selectedCount === 0) {
    return "Select at least one eligible simulation-passed scope.";
  }
  if (context.role !== "admin") {
    return "Staging verification approval requires the admin role.";
  }
  if (context.assuranceLevel !== "aal2") {
    return "Staging verification approval requires verified MFA step-up (AAL2).";
  }
  return undefined;
}
