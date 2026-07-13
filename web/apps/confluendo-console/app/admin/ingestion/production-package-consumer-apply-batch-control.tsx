"use client";

import { useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import type { AdminAssuranceLevel, AdminRole } from "@confluendo/ingestion-platform/admin-auth";
import {
  APPLY_AMBIGUOUS_RESULT_MESSAGE,
  APPLY_DURATION_NOTE,
  APPLY_IN_FLIGHT_DO_NOT_RETRY,
  APPLY_REQUEST_TIMEOUT_MS,
  applyButtonDisabledReason,
  applyButtonLabel,
  applyInFlightStatusLines,
  isAmbiguousBatchApplyResponse,
  summarizeBatchApplyStopOnFailure,
  type ApplyOperationPhase,
  type ApplyPreflightPhase
} from "@confluendo/ingestion-platform/core/delivery-operator-presenter";
import { friendlyUnit } from "./ingestion-console-labels";

type DashboardSource = "live" | "sample" | "error";

type WaveItem = {
  unitKey: string;
  packageId?: string | null;
  status: string;
  consumerApplyStatus?: string | null;
};

type BatchPreflight = {
  waveKey: string;
  targets: Array<{
    unitKey: string;
    packageId: string;
    checksum: string;
    itemCount: number;
    pendingItemCount: number;
    targetTables: string[];
  }>;
  skippedAppliedPackageIds: string[];
  preflightSummary: {
    packageCount: number;
    totalInboxItems: number;
    pendingItemCount: number;
    appliedItemCount: number;
    targetTables: string[];
  };
};

type BatchApplySuccessPayload = {
  ok: true;
  appliedPackageIds: string[];
  skippedAppliedPackageIds: string[];
  auditIds: string[];
};

type BatchApplyFailurePayload = {
  ok: false;
  decision?: "blocked" | "failed";
  blocks?: { code: string }[];
  error?: string;
  failedPackageId?: string;
  skippedAppliedPackageIds?: string[];
};

type Decision =
  | { state: "idle" }
  | {
      state: "applied";
      appliedPackageIds: string[];
      skippedAppliedPackageIds: string[];
      auditIds: string[];
    }
  | { state: "blocked"; blocks: string[] }
  | {
      state: "partial_failure";
      message: string;
      failedPackageId?: string;
      appliedCount: number;
      notAttemptedCount: number;
      skippedCount: number;
    }
  | { state: "ambiguous" }
  | { state: "validation"; message: string };

const freshStepUpHref =
  "/admin/mfa/challenge?reason=fresh_step_up_required&next=%2Fadmin%2Fingestion";

const blockLabels: Record<string, string> = {
  role_denied: "Requires the ingestion_admin role (admin).",
  scope_denied: "This admin account is not scoped to this ingestion project.",
  mfa_required: "Requires verified MFA step-up (AAL2).",
  fresh_step_up_required: "Requires a fresh MFA step-up.",
  audit_reason_required: "A non-empty audit reason is required.",
  apply_not_configured: "Consumer apply database URL is not configured on the server.",
  wave_not_found: "Production package wave was not found.",
  wave_not_deliverable: "Wave must be delivered before consumer apply.",
  no_apply_targets: "No delivered packages with pending apply items were selected.",
  package_not_in_wave: "Package is not part of this wave.",
  shipment_not_delivered: "Shipment must be delivered with pending items.",
  already_applied: "Package has already been applied.",
  preflight_failed: "Batch apply preflight could not be loaded."
};

export function ProductionPackageConsumerApplyBatchControl({
  projectKey,
  waveKey,
  items,
  context
}: {
  projectKey: string;
  waveKey: string;
  items: WaveItem[];
  context: {
    role: AdminRole;
    assuranceLevel: AdminAssuranceLevel;
    source: DashboardSource;
  };
}) {
  const eligibleItems = items.filter((item) => isConsumerApplyEligible(item));
  const [selectedPackageIds, setSelectedPackageIds] = useState<string[]>(
    eligibleItems.map((item) => item.packageId!).filter(Boolean)
  );
  const [reason, setReason] = useState("");
  const [preflight, setPreflight] = useState<BatchPreflight | null>(null);
  const [preflightBlocks, setPreflightBlocks] = useState<string[]>([]);
  const [preflightPhase, setPreflightPhase] = useState<ApplyPreflightPhase>("idle");
  const [applyPhase, setApplyPhase] = useState<ApplyOperationPhase>("idle");
  const [applyElapsedMs, setApplyElapsedMs] = useState(0);
  const [decision, setDecision] = useState<Decision>({ state: "idle" });
  const inFlightRef = useRef(false);
  const applyStartedAtRef = useRef<number | null>(null);
  const router = useRouter();
  const contextDisabledReason = disabledReasonFor(context, eligibleItems.length);
  const operationBusy = applyPhase === "applying" || applyPhase === "refreshing";

  const buttonDisabledReason = applyButtonDisabledReason({
    contextDisabledReason,
    preflightPhase,
    applyPhase,
    inFlight: operationBusy,
    selectedCount: selectedPackageIds.length,
    auditReason: reason,
    preflightBlocks,
    hasPreflight: Boolean(preflight)
  });

  useEffect(() => {
    if (disabledReasonFor(context, eligibleItems.length) || selectedPackageIds.length === 0) {
      setPreflight(null);
      setPreflightBlocks([]);
      setPreflightPhase("idle");
      return;
    }
    let cancelled = false;
    setPreflight(null);
    setPreflightBlocks([]);
    setPreflightPhase("checking");
    const params = new URLSearchParams({
      projectKey,
      waveKey,
      packageIds: selectedPackageIds.join(",")
    });
    void (async () => {
      try {
        const response = await fetch(
          `/api/admin/ingestion/production-package-wave/apply-wave/preflight?${params}`
        );
        const payload = (await response.json().catch(() => null)) as
          | { ok: true } & BatchPreflight
          | { ok: false; blocks?: { code: string }[]; error?: string }
          | null;
        if (cancelled) {
          return;
        }
        if (!payload?.ok) {
          setPreflight(null);
          setPreflightBlocks(payload?.blocks?.map((block) => block.code) ?? ["preflight_failed"]);
          setPreflightPhase("idle");
          return;
        }
        setPreflight(payload);
        setPreflightBlocks([]);
        setPreflightPhase("idle");
      } catch {
        if (!cancelled) {
          setPreflight(null);
          setPreflightBlocks(["preflight_failed"]);
          setPreflightPhase("idle");
        }
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [context, eligibleItems.length, projectKey, selectedPackageIds, waveKey]);

  useEffect(() => {
    setApplyPhase((phase) => (phase === "completed" ? "idle" : phase));
    setDecision({ state: "idle" });
  }, [selectedPackageIds]);

  useEffect(() => {
    if (applyPhase !== "applying" || applyStartedAtRef.current === null) {
      setApplyElapsedMs(0);
      return;
    }
    const startedAt = applyStartedAtRef.current;
    const tick = () => setApplyElapsedMs(Date.now() - startedAt);
    tick();
    const intervalId = window.setInterval(tick, 1000);
    return () => window.clearInterval(intervalId);
  }, [applyPhase]);

  if (eligibleItems.length === 0) {
    return null;
  }

  const buttonLabel = applyButtonLabel({
    preflightPhase,
    applyPhase,
    selectedCount: selectedPackageIds.length
  });
  const inFlightStatus =
    applyPhase === "applying"
      ? applyInFlightStatusLines({
          selectedCount: selectedPackageIds.length,
          elapsedMs: applyElapsedMs
        })
      : null;

  return (
    <div className="admin-canary-control admin-batch-wave-approval-control">
      <p className="admin-kicker">IP-18.8.5 · batch apply to Vamo</p>
      <h3>Apply selected packages to Vamo</h3>
      <p className="admin-canary-note">
        Applies delivered inbox packages sequentially through the existing consumer-owned apply
        function. Stops on first failure. Already-applied packages are skipped. {APPLY_DURATION_NOTE}
      </p>

      <div className="admin-table-wrap">
        <table className="admin-target-table admin-queue-table">
          <thead>
            <tr>
              <th />
              <th>Scope</th>
              <th>Package id</th>
              <th>Status</th>
            </tr>
          </thead>
          <tbody>
            {eligibleItems.map((item) => (
              <tr key={item.unitKey}>
                <td>
                  <input
                    type="checkbox"
                    checked={selectedPackageIds.includes(item.packageId!)}
                    onChange={() => togglePackage(item.packageId!)}
                    disabled={operationBusy || preflightPhase === "checking"}
                  />
                </td>
                <td>
                  <strong>{friendlyUnit(item.unitKey)}</strong>
                  <code className="admin-evidence-code">{item.unitKey}</code>
                </td>
                <td>
                  <code>{item.packageId}</code>
                </td>
                <td>{item.consumerApplyStatus ?? item.status}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {preflightPhase === "checking" ? (
        <p className="admin-action-status" role="status">
          Checking apply preflight for {selectedPackageIds.length} selected package
          {selectedPackageIds.length === 1 ? "" : "s"}…
        </p>
      ) : null}

      {preflight ? (
        <div className="admin-command-result" role="status">
          <strong>Batch apply preflight</strong>
          <span>
            {preflight.targets.length} package(s) · {preflight.preflightSummary.totalInboxItems}{" "}
            inbox item(s) · {preflight.preflightSummary.pendingItemCount} pending
          </span>
          <span>
            Target tables: {preflight.preflightSummary.targetTables.join(", ") || "—"}
          </span>
          {preflight.skippedAppliedPackageIds.length > 0 ? (
            <span>
              Skipping {preflight.skippedAppliedPackageIds.length} already-applied package(s).
            </span>
          ) : null}
        </div>
      ) : null}

      {preflightBlocks.length > 0 ? (
        <div className="admin-command-result admin-command-result-error" role="alert">
          <strong>Batch apply preflight blocked</strong>
          <ul>
            {preflightBlocks.map((code) => (
              <li key={code}>{blockLabels[code] ?? code}</li>
            ))}
          </ul>
        </div>
      ) : null}

      {inFlightStatus ? (
        <div className="admin-apply-in-flight-panel admin-command-result" role="status" aria-live="polite">
          <strong>{inFlightStatus.headline}</strong>
          <span>{inFlightStatus.durationLine}</span>
          <span>{inFlightStatus.guidanceLine}</span>
        </div>
      ) : null}

      <label className="admin-canary-reason">
        <span>Audit reason</span>
        <textarea
          value={reason}
          onChange={(event) => setReason(event.target.value)}
          rows={2}
          maxLength={280}
          placeholder="Why apply these delivered packages to Vamo now?"
          disabled={Boolean(contextDisabledReason) || operationBusy}
        />
      </label>

      <div className="admin-action-row">
        <button
          type="button"
          className="admin-command admin-command-primary admin-stateful-command"
          data-state={
            preflightPhase === "checking" || operationBusy
              ? "busy"
              : buttonDisabledReason
                ? "unavailable"
                : "ready"
          }
          onClick={() => void submit()}
          disabled={Boolean(buttonDisabledReason)}
        >
          {buttonLabel}
        </button>
        {buttonDisabledReason ? (
          <p className="admin-action-status" data-state="unavailable">
            {buttonDisabledReason}
          </p>
        ) : null}
      </div>

      <DecisionView
        decision={decision}
        applyPhase={applyPhase}
        onRefreshDeliveryStatus={() => refreshDeliveryStatus()}
      />
    </div>
  );

  function togglePackage(packageId: string) {
    if (operationBusy || preflightPhase === "checking") {
      return;
    }
    if (selectedPackageIds.includes(packageId)) {
      setSelectedPackageIds(selectedPackageIds.filter((id) => id !== packageId));
      return;
    }
    setSelectedPackageIds([...selectedPackageIds, packageId]);
  }

  function refreshDeliveryStatus() {
    setApplyPhase("refreshing");
    router.refresh();
    setApplyPhase("idle");
    setDecision({ state: "idle" });
  }

  async function submit() {
    if (inFlightRef.current) {
      return;
    }
    if (!reason.trim()) {
      setDecision({ state: "validation", message: "Audit reason is required." });
      return;
    }
    if (buttonDisabledReason) {
      return;
    }
    inFlightRef.current = true;
    applyStartedAtRef.current = Date.now();
    setApplyElapsedMs(0);
    setApplyPhase("applying");
    setDecision({ state: "idle" });

    const abortController = new AbortController();
    const timeoutId = window.setTimeout(() => abortController.abort(), APPLY_REQUEST_TIMEOUT_MS);

    try {
      const response = await fetch("/api/admin/ingestion/production-package-wave/apply-wave", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          projectKey,
          waveKey,
          packageIds: selectedPackageIds,
          auditReason: reason.trim(),
          confirmation: "YES"
        }),
        signal: abortController.signal
      });
      const payload = (await response.json().catch(() => null)) as
        | BatchApplySuccessPayload
        | BatchApplyFailurePayload
        | null;

      if (isAmbiguousBatchApplyResponse({ status: response.status, payload })) {
        setDecision({ state: "ambiguous" });
        setApplyPhase("idle");
        return;
      }

      if (!payload?.ok) {
        if (payload?.blocks) {
          const blocks = payload.blocks.map((block) => block.code);
          if (blocks.includes("mfa_required") || blocks.includes("fresh_step_up_required")) {
            window.location.assign(freshStepUpHref);
            return;
          }
          setDecision({ state: "blocked", blocks });
          setApplyPhase("idle");
          return;
        }
        if (payload?.decision === "failed") {
          const summary = summarizeBatchApplyStopOnFailure({
            selectedPackageIds,
            failedPackageId: payload.failedPackageId,
            skippedAppliedPackageIds: payload.skippedAppliedPackageIds
          });
          setDecision({
            state: "partial_failure",
            message: payload.error ?? "Consumer apply reported a stop-on-first-failure result.",
            failedPackageId: payload.failedPackageId,
            appliedCount: summary.appliedCount,
            notAttemptedCount: summary.notAttemptedCount,
            skippedCount: summary.skippedCount
          });
          setApplyPhase("idle");
          return;
        }
        setDecision({
          state: "validation",
          message: payload?.error ?? "The apply request was refused before packages were applied."
        });
        setApplyPhase("idle");
        return;
      }

      setDecision({
        state: "applied",
        appliedPackageIds: payload.appliedPackageIds,
        skippedAppliedPackageIds: payload.skippedAppliedPackageIds,
        auditIds: payload.auditIds
      });
      setApplyPhase("refreshing");
      router.refresh();
      setApplyPhase("completed");
    } catch {
      setDecision({ state: "ambiguous" });
      setApplyPhase("idle");
    } finally {
      window.clearTimeout(timeoutId);
      inFlightRef.current = false;
      applyStartedAtRef.current = null;
    }
  }
}

function DecisionView({
  decision,
  applyPhase,
  onRefreshDeliveryStatus
}: {
  decision: Decision;
  applyPhase: ApplyOperationPhase;
  onRefreshDeliveryStatus: () => void;
}) {
  if (decision.state === "idle") {
    return null;
  }
  if (decision.state === "applied") {
    return (
      <div className="admin-command-result admin-command-result-ok" role="status">
        <strong>
          {applyPhase === "completed" ? "Batch consumer apply completed" : "Batch consumer apply succeeded"}
        </strong>
        <span>Applied {decision.appliedPackageIds.length} package(s)</span>
        {decision.skippedAppliedPackageIds.length > 0 ? (
          <span>Skipped {decision.skippedAppliedPackageIds.length} already-applied package(s)</span>
        ) : null}
        <span>Audit ids: {decision.auditIds.join(", ")}</span>
        {applyPhase === "refreshing" ? (
          <span>Refreshing delivery status…</span>
        ) : applyPhase === "completed" ? (
          <span>Delivery status refresh completed.</span>
        ) : null}
      </div>
    );
  }
  if (decision.state === "partial_failure") {
    return (
      <div className="admin-command-result admin-command-result-error" role="alert">
        <strong>{decision.message}</strong>
        <span>Applied before stop: {decision.appliedCount} package(s)</span>
        {decision.skippedCount > 0 ? (
          <span>Skipped as already applied: {decision.skippedCount} package(s)</span>
        ) : null}
        {decision.failedPackageId ? (
          <span>
            Stopped on package: <code>{decision.failedPackageId}</code>
          </span>
        ) : null}
        {decision.notAttemptedCount > 0 ? (
          <span>Not attempted after stop: {decision.notAttemptedCount} package(s)</span>
        ) : null}
        <span>Refresh delivery telemetry before retrying the remaining packages.</span>
        <button
          type="button"
          className="admin-command admin-command-neutral admin-inline-action"
          onClick={onRefreshDeliveryStatus}
        >
          Refresh delivery status
        </button>
      </div>
    );
  }
  if (decision.state === "ambiguous") {
    return (
      <div className="admin-command-result admin-command-result-watch" role="alert">
        <strong>{APPLY_AMBIGUOUS_RESULT_MESSAGE}</strong>
        <span>{APPLY_IN_FLIGHT_DO_NOT_RETRY}</span>
        <button
          type="button"
          className="admin-command admin-command-neutral admin-inline-action"
          onClick={onRefreshDeliveryStatus}
        >
          Refresh delivery status
        </button>
      </div>
    );
  }
  if (decision.state === "blocked") {
    return (
      <div className="admin-command-result admin-command-result-error" role="alert">
        <strong>Batch apply blocked</strong>
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

function disabledReasonFor(
  context: { role: AdminRole; assuranceLevel: AdminAssuranceLevel; source: DashboardSource },
  eligibleCount: number
): string | undefined {
  if (context.source !== "live") {
    return "Batch consumer apply requires a live control plane.";
  }
  if (eligibleCount === 0) {
    return "No delivered packages with pending apply items are available.";
  }
  if (context.role !== "admin") {
    return "Consumer apply requires the admin role.";
  }
  if (context.assuranceLevel !== "aal2") {
    return "Consumer apply requires verified MFA step-up (AAL2).";
  }
  return undefined;
}

function isConsumerApplyEligible(item: WaveItem): boolean {
  if (!item.packageId) {
    return false;
  }
  if (item.consumerApplyStatus === "applied" || item.consumerApplyStatus === "failed") {
    return false;
  }
  return (
    item.consumerApplyStatus === "pending" ||
    item.status === "delivered" ||
    item.status === "production_package_delivered" ||
    item.status === "consumer_apply_pending"
  );
}
