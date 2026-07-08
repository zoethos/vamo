"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import type { AdminAssuranceLevel, AdminRole } from "@confluendo/ingestion-platform/admin-auth";

type DashboardSource = "live" | "sample" | "error";

type BatchQueueContext = {
  role: AdminRole;
  assuranceLevel: AdminAssuranceLevel;
  source: DashboardSource;
};

type BatchQueuePlan = {
  targetEnvironment: string;
  fromStatus: string;
  toStatus: string;
  itemCount: number;
};

type Decision =
  | { state: "idle" }
  | { state: "running" }
  | {
      state: "scheduled";
      auditId: string | null;
      scheduledCount: number;
      alreadyScheduledCount: number;
      plan: BatchQueuePlan;
    }
  | { state: "blocked"; blocks: string[] }
  | { state: "error"; message: string; code?: string };

const blockLabels: Record<string, string> = {
  role_denied: "Scheduling requires the operator or admin role.",
  scope_denied: "This admin account is not scoped to this ingestion project.",
  mfa_required: "Scheduling requires MFA step-up (AAL2).",
  audit_reason_required: "A non-empty audit reason is required.",
  unsafe_safety_mode: "Only dry-run batch plans can be scheduled.",
  target_environment_required: "The batch plan must declare its target environment.",
  no_eligible_items: "No ready_for_dry_run queue items remain to schedule."
};

const mfaHref = "/admin/mfa/challenge?reason=mfa_challenge_required&next=%2Fadmin%2Fingestion";

export function BatchQueueScheduleControl({
  projectKey,
  targetKey,
  eligibleCount,
  context
}: {
  projectKey: string;
  targetKey: string;
  eligibleCount: number;
  context: BatchQueueContext;
}) {
  const [reason, setReason] = useState("");
  const [decision, setDecision] = useState<Decision>({ state: "idle" });
  const inFlightRef = useRef(false);
  const router = useRouter();
  const pending = decision.state === "running";
  const disabledReason = disabledReasonFor(context, eligibleCount);

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
      const response = await fetch("/api/admin/ingestion/batch-queue/schedule", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          projectKey,
          targetKey,
          auditReason: reason.trim()
        })
      });
      const payload = (await response.json().catch(() => null)) as
        | {
            ok: true;
            decision: "scheduled";
            auditId: string | null;
            scheduledCount: number;
            alreadyScheduledCount: number;
            plan: BatchQueuePlan;
          }
        | { ok: false; decision?: "blocked"; blocks?: { code: string }[]; error?: string; code?: string }
        | null;

      if (!payload) {
        setDecision({ state: "error", message: "The schedule request failed." });
        return;
      }
      if (payload.ok) {
        setDecision({
          state: "scheduled",
          auditId: payload.auditId,
          scheduledCount: payload.scheduledCount,
          alreadyScheduledCount: payload.alreadyScheduledCount,
          plan: payload.plan
        });
        router.refresh();
        return;
      }
      if (payload.decision === "blocked" && Array.isArray(payload.blocks)) {
        const blocks = payload.blocks.map((block) => block.code);
        if (blocks.includes("mfa_required")) {
          window.location.assign(mfaHref);
          return;
        }
        setDecision({ state: "blocked", blocks });
        return;
      }
      setDecision({
        state: "error",
        message: payload.error ?? "The schedule request was refused.",
        code: payload.code
      });
    } catch {
      setDecision({ state: "error", message: "The schedule request failed to send." });
    } finally {
      inFlightRef.current = false;
    }
  }

  return (
    <div className="admin-canary-control admin-batch-schedule-control">
      <p className="admin-kicker">IP-18.3 · schedule dry-run</p>
      <h3>Schedule persisted batch queue</h3>
      <p className="admin-canary-note">
        Advances eligible queue rows from ready_for_dry_run to dry_run_ready in the
        Confluendo control plane. This does not execute ingestion or write to Vamo
        staging or production.
      </p>
      <div className="admin-canary-fields">
        <label>
          <span>Target</span>
          <input type="text" value={targetKey} readOnly disabled />
        </label>
        <label>
          <span>Eligible units</span>
          <input type="text" value={String(eligibleCount)} readOnly disabled />
        </label>
      </div>
      <label className="admin-canary-reason">
        <span>Audit reason</span>
        <textarea
          value={reason}
          onChange={(event) => setReason(event.target.value)}
          rows={2}
          maxLength={280}
          placeholder="Why should this batch move into dry-run scheduling now?"
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
          {pending ? "Scheduling..." : "Schedule dry-run batch"}
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

function DecisionView({ decision }: { decision: Decision }) {
  if (decision.state === "idle" || decision.state === "running") {
    return null;
  }
  if (decision.state === "scheduled") {
    return (
      <div className="admin-command-result admin-command-result-ok" role="status">
        <strong>Dry-run batch scheduled</strong>
        <span>
          {decision.scheduledCount} newly scheduled · {decision.alreadyScheduledCount} total dry-run ready
        </span>
        <span>
          {decision.plan.fromStatus} → {decision.plan.toStatus} · {decision.plan.targetEnvironment}
        </span>
        {decision.auditId ? <span>Audit id: {decision.auditId}</span> : null}
      </div>
    );
  }
  if (decision.state === "blocked") {
    return (
      <div className="admin-command-result admin-command-result-error" role="alert">
        <strong>Batch scheduling blocked</strong>
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
      {decision.code ? <span>{decision.code}</span> : null}
    </div>
  );
}

function disabledReasonFor(context: BatchQueueContext, eligibleCount: number): string | undefined {
  if (context.source === "error") {
    return "Live batch queue read failed; scheduling is disabled.";
  }
  if (context.source !== "live") {
    return "Batch scheduling requires a live control plane.";
  }
  if (eligibleCount === 0) {
    return "No ready_for_dry_run units remain to schedule.";
  }
  if (context.role === "viewer") {
    return "Viewers can inspect the queue but cannot schedule it.";
  }
  if (context.assuranceLevel !== "aal2") {
    return "Batch scheduling requires MFA step-up (AAL2).";
  }
  return undefined;
}
