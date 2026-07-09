"use client";

import { useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import type { AdminAssuranceLevel, AdminRole } from "@confluendo/ingestion-platform/admin-auth";
import type { AutonomyRampCardPresentation, AutonomyRampMode } from "@confluendo/ingestion-platform/core";

type DashboardSource = "live" | "sample" | "error";

type RampContext = {
  role: AdminRole;
  assuranceLevel: AdminAssuranceLevel;
  source: DashboardSource;
};

type Decision =
  | { state: "idle" }
  | { state: "running" }
  | {
      state: "changed";
      direction: "promotion" | "demotion";
      fromMode: AutonomyRampMode;
      toMode: AutonomyRampMode;
      auditId: string;
    }
  | { state: "blocked"; blocks: string[]; warnings?: string[] }
  | { state: "error"; message: string; code?: string };

const blockLabels: Record<string, string> = {
  same_mode: "The requested ramp mode is already active.",
  unknown_mode: "The requested ramp mode is not recognized.",
  skips_required_ramp: "Ramp changes must move one adjacent step up at a time.",
  missing_audit_reason: "A non-empty audit reason is required.",
  missing_actor_identity: "An authenticated operator identity is required.",
  actor_not_operator: "Ramp promotion requires an admin operator.",
  fresh_step_up_required: "Ramp promotion requires a fresh AAL2 MFA step-up.",
  active_critical_blockers: "Resolve active queue blockers before widening the ramp.",
  production_handoff_not_ready: "Steady-state ramp is locked until production handoff is enabled.",
  advisory_warnings_unacknowledged: "Acknowledge advisory warnings before promoting.",
  ramp_mode_conflict: "The ramp mode changed. Refresh before trying again.",
  confirmed_mode_mismatch: "Typed confirmation must exactly match the target ramp mode."
};

const freshStepUpHref =
  "/admin/mfa/challenge?reason=fresh_step_up_required&next=%2Fadmin%2Fingestion";

export function AutonomyRampControl({
  projectKey,
  policyKey,
  rampCard,
  context
}: {
  projectKey: string;
  policyKey: string;
  rampCard: AutonomyRampCardPresentation;
  context: RampContext;
}) {
  const [auditReason, setAuditReason] = useState("");
  const [confirmedMode, setConfirmedMode] = useState("");
  const [demotionMode, setDemotionMode] = useState<AutonomyRampMode | "">("");
  const [acknowledgedWarnings, setAcknowledgedWarnings] = useState(false);
  const [decision, setDecision] = useState<Decision>({ state: "idle" });
  const inFlightRef = useRef(false);
  const router = useRouter();
  const pending = decision.state === "running";

  const promoteDisabledReason = useMemo(
    () => promotionDisabledReason(context, rampCard),
    [context, rampCard]
  );
  const demoteDisabledReason = useMemo(
    () => demotionDisabledReason(context, rampCard, demotionMode),
    [context, rampCard, demotionMode]
  );

  async function submitChange(requestedMode: AutonomyRampMode, direction: "promotion" | "demotion") {
    if (inFlightRef.current) {
      return;
    }
    if (!auditReason.trim()) {
      setDecision({ state: "error", message: "Audit reason is required." });
      return;
    }
    if (confirmedMode.trim() !== requestedMode) {
      setDecision({
        state: "error",
        message: `Type ${requestedMode} to confirm the target ramp mode.`
      });
      return;
    }
    if (
      direction === "promotion" &&
      rampCard.advisoryWarnings.length > 0 &&
      !acknowledgedWarnings
    ) {
      setDecision({
        state: "error",
        message: "Acknowledge the advisory warnings before promoting."
      });
      return;
    }

    inFlightRef.current = true;
    setDecision({ state: "running" });

    try {
      const response = await fetch("/api/admin/ingestion/autonomy/ramp", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          projectKey,
          policyKey,
          expectedCurrentMode: rampCard.currentMode,
          requestedMode,
          auditReason: auditReason.trim(),
          confirmedMode: confirmedMode.trim(),
          acknowledgedWarnings: direction === "promotion" ? acknowledgedWarnings : undefined
        })
      });
      const payload = (await response.json().catch(() => null)) as
        | {
            ok: true;
            decision: "promotion" | "demotion";
            fromMode: AutonomyRampMode;
            toMode: AutonomyRampMode;
            auditId: string;
          }
        | {
            ok: false;
            decision?: "blocked";
            blocks?: { code: string }[];
            warnings?: string[];
            error?: string;
            code?: string;
          }
        | null;

      if (!payload) {
        setDecision({ state: "error", message: "The ramp change request failed." });
        return;
      }
      if (payload.ok) {
        setDecision({
          state: "changed",
          direction: payload.decision,
          fromMode: payload.fromMode,
          toMode: payload.toMode,
          auditId: payload.auditId
        });
        setAuditReason("");
        setConfirmedMode("");
        setDemotionMode("");
        setAcknowledgedWarnings(false);
        router.refresh();
        return;
      }
      if (payload.decision === "blocked" && Array.isArray(payload.blocks)) {
        const blocks = payload.blocks.map((block) => block.code);
        if (blocks.includes("fresh_step_up_required")) {
          window.location.assign(freshStepUpHref);
          return;
        }
        setDecision({
          state: "blocked",
          blocks,
          warnings: payload.warnings
        });
        return;
      }
      setDecision({
        state: "error",
        message: payload.error ?? "The ramp change request was refused.",
        code: payload.code
      });
    } catch {
      setDecision({ state: "error", message: "The ramp change request failed to send." });
    } finally {
      inFlightRef.current = false;
    }
  }

  return (
    <section className="admin-agent-uex-panel admin-agent-ramp-panel" aria-labelledby="agent-ramp-heading">
      <div className="admin-agent-uex-panel-header">
        <h3 id="agent-ramp-heading">Ramp mode</h3>
        <span className="admin-agent-uex-panel-count">{rampCard.currentModeLabel}</span>
      </div>

      <p className="admin-agent-ramp-note">
        Promotion widens autonomous cycle limits inside the owner ceiling. It does not widen live
        staging writes — autonomous staging verification batches stay capped separately. Production
        delivery packages remain governed by IP-18.6.
      </p>

      <dl className="admin-agent-ramp-summary">
        <div>
          <dt>Current ramp mode</dt>
          <dd>
            <strong>{rampCard.currentModeLabel}</strong>
            <span>
              <code>{rampCard.currentMode}</code>
            </span>
          </dd>
        </div>
        <div>
          <dt>Next allowed ramp mode</dt>
          <dd>
            {rampCard.nextMode ? (
              <>
                <strong>{rampCard.nextModeLabel}</strong>
                <span>
                  <code>{rampCard.nextMode}</code>
                </span>
              </>
            ) : (
              "No further promotion available"
            )}
          </dd>
        </div>
      </dl>

      <div className="admin-table-wrap">
        <table className="admin-target-table admin-agent-ramp-bounds-table">
          <thead>
            <tr>
              <th>Bound</th>
              <th>Owner ceiling</th>
              <th>Ramp profile cap</th>
              <th>Effective cycle limits</th>
            </tr>
          </thead>
          <tbody>
            <BoundsRow label="Scopes per cycle" owner={rampCard.ownerCeiling.maxUnitsPerCycle} profile={rampCard.profileCaps.maxUnitsPerCycle} effective={rampCard.effectiveBounds.maxUnitsPerCycle} />
            <BoundsRow label="Target writes per cycle" owner={rampCard.ownerCeiling.maxRowsPerCycle} profile={rampCard.profileCaps.maxRowsPerCycle} effective={rampCard.effectiveBounds.maxRowsPerCycle} />
            <BoundsRow label="Cycles per day" owner={rampCard.ownerCeiling.maxCyclesPerDay} profile={rampCard.profileCaps.maxCyclesPerDay} effective={rampCard.effectiveBounds.maxCyclesPerDay} />
            <BoundsRow label="Scopes per day" owner={rampCard.ownerCeiling.maxUnitsPerDay} profile={rampCard.profileCaps.maxUnitsPerDay} effective={rampCard.effectiveBounds.maxUnitsPerDay} />
            <BoundsRow label="Target writes per day" owner={rampCard.ownerCeiling.maxRowsPerDay} profile={rampCard.profileCaps.maxRowsPerDay} effective={rampCard.effectiveBounds.maxRowsPerDay} />
          </tbody>
        </table>
      </div>

      <div className="admin-agent-ramp-evidence">
        <h4>Readiness evidence</h4>
        <dl className="admin-agent-uex-meta admin-agent-ramp-readiness">
          {rampCard.readinessEvidence.map((item) => (
            <div key={item.label}>
              <dt>{item.label}</dt>
              <dd>{item.value}</dd>
            </div>
          ))}
        </dl>
      </div>

      {rampCard.advisoryWarnings.length > 0 ? (
        <div className="admin-agent-ramp-warnings" role="note">
          <h4>Advisory warnings</h4>
          <ul>
            {rampCard.advisoryWarnings.map((warning) => (
              <li key={warning}>{warning}</li>
            ))}
          </ul>
        </div>
      ) : null}

      {(rampCard.rampWarnings.length > 0 || rampCard.activeBlockerCount > 0) && (
        <div className="admin-agent-ramp-blockers" role="alert">
          {rampCard.activeBlockerCount > 0 ? (
            <p>
              <strong>{rampCard.activeBlockerCount}</strong> active queue blocker(s) must be cleared
              before promotion.
            </p>
          ) : null}
          {rampCard.rampWarnings.length > 0 ? (
            <ul>
              {rampCard.rampWarnings.map((warning) => (
                <li key={warning}>{warning}</li>
              ))}
            </ul>
          ) : null}
        </div>
      )}

      <div className="admin-agent-ramp-fields">
        <label>
          <span>Audit reason</span>
          <textarea
            value={auditReason}
            onChange={(event) => setAuditReason(event.target.value)}
            rows={2}
            maxLength={280}
            placeholder="Why change the ramp mode now?"
            disabled={pending}
          />
        </label>
        <label>
          <span>Type target ramp mode to confirm</span>
          <input
            type="text"
            value={confirmedMode}
            onChange={(event) => setConfirmedMode(event.target.value)}
            placeholder="e.g. volume_ramp"
            disabled={pending}
          />
        </label>
        {rampCard.advisoryWarnings.length > 0 ? (
          <label className="admin-agent-ramp-ack">
            <input
              type="checkbox"
              checked={acknowledgedWarnings}
              onChange={(event) => setAcknowledgedWarnings(event.target.checked)}
              disabled={pending}
            />
            <span>I reviewed the advisory warnings before promoting.</span>
          </label>
        ) : null}
      </div>

      <div className="admin-action-row admin-agent-ramp-actions">
        {rampCard.nextMode ? (
          <button
            type="button"
            className="admin-command admin-command-primary admin-stateful-command"
            data-state={pending ? "busy" : promoteDisabledReason ? "unavailable" : "ready"}
            onClick={() => void submitChange(rampCard.nextMode!, "promotion")}
            disabled={Boolean(promoteDisabledReason) || pending}
            title={promoteDisabledReason ?? undefined}
          >
            {pending ? "Applying ramp change..." : `Promote to ${rampCard.nextModeLabel ?? rampCard.nextMode}`}
          </button>
        ) : null}
        {promoteDisabledReason ? (
          <p className="admin-action-status" data-state="unavailable">
            Promotion unavailable: {promoteDisabledReason}
          </p>
        ) : null}
      </div>

      {rampCard.demotionModes.length > 0 ? (
        <div className="admin-agent-ramp-demotion">
          <h4>Reduce ramp</h4>
          <p className="admin-agent-ramp-note">
            Demotion narrows autonomous bounds immediately. Fresh MFA is not required, but an audit
            reason and typed confirmation are still required.
          </p>
          <label>
            <span>Target lower ramp mode</span>
            <select
              value={demotionMode}
              onChange={(event) => setDemotionMode(event.target.value as AutonomyRampMode | "")}
              disabled={pending}
            >
              <option value="">Select a lower ramp mode</option>
              {rampCard.demotionModes.map((option) => (
                <option key={option.mode} value={option.mode}>
                  {option.label} ({option.mode})
                </option>
              ))}
            </select>
          </label>
          <div className="admin-action-row">
            <button
              type="button"
              className="admin-command admin-command-neutral admin-stateful-command"
              data-state={pending ? "busy" : demoteDisabledReason ? "unavailable" : "ready"}
              onClick={() => demotionMode && void submitChange(demotionMode, "demotion")}
              disabled={Boolean(demoteDisabledReason) || pending || !demotionMode}
              title={demoteDisabledReason ?? undefined}
            >
              Reduce ramp
            </button>
            {demoteDisabledReason ? (
              <p className="admin-action-status" data-state="unavailable">
                Demotion unavailable: {demoteDisabledReason}
              </p>
            ) : null}
          </div>
        </div>
      ) : null}

      <DecisionView decision={decision} />
    </section>
  );
}

function BoundsRow({
  label,
  owner,
  profile,
  effective
}: {
  label: string;
  owner: number;
  profile: number;
  effective: number;
}) {
  return (
    <tr>
      <td>{label}</td>
      <td>{owner}</td>
      <td>{profile}</td>
      <td>
        <strong>{effective}</strong>
      </td>
    </tr>
  );
}

function DecisionView({ decision }: { decision: Decision }) {
  if (decision.state === "idle" || decision.state === "running") {
    return null;
  }
  if (decision.state === "changed") {
    return (
      <div className="admin-command-result admin-command-result-ok" role="status">
        <strong>Ramp mode updated (control plane only)</strong>
        <span>
          {decision.fromMode} → {decision.toMode} · audit id {decision.auditId}
        </span>
        <span>No provider calls, staging writes, or production delivery occurred.</span>
      </div>
    );
  }
  if (decision.state === "blocked") {
    return (
      <div className="admin-command-result admin-command-result-error" role="alert">
        <strong>Ramp change blocked</strong>
        <ul>
          {decision.blocks.map((code) => (
            <li key={code}>{blockLabels[code] ?? code}</li>
          ))}
        </ul>
        {decision.warnings && decision.warnings.length > 0 ? (
          <ul>
            {decision.warnings.map((warning) => (
              <li key={warning}>{warning}</li>
            ))}
          </ul>
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

function promotionDisabledReason(
  context: RampContext,
  rampCard: AutonomyRampCardPresentation
): string | undefined {
  if (context.source === "error") {
    return "Live control-plane read failed.";
  }
  if (context.source !== "live") {
    return "Ramp changes require a live control plane.";
  }
  if (!rampCard.nextMode) {
    return "No adjacent promotion is available.";
  }
  if (context.role !== "admin") {
    return "Ramp promotion requires the admin role.";
  }
  if (context.assuranceLevel !== "aal2") {
    return "Ramp promotion requires verified MFA step-up (AAL2).";
  }
  if (rampCard.activeBlockerCount > 0) {
    return "Resolve active queue blockers before promoting.";
  }
  return undefined;
}

function demotionDisabledReason(
  context: RampContext,
  rampCard: AutonomyRampCardPresentation,
  demotionMode: AutonomyRampMode | ""
): string | undefined {
  if (context.source === "error") {
    return "Live control-plane read failed.";
  }
  if (context.source !== "live") {
    return "Ramp changes require a live control plane.";
  }
  if (context.role !== "admin") {
    return "Ramp demotion requires the admin role.";
  }
  if (rampCard.demotionModes.length === 0) {
    return "Already at the lowest ramp mode.";
  }
  if (!demotionMode) {
    return "Select a lower ramp mode.";
  }
  return undefined;
}
