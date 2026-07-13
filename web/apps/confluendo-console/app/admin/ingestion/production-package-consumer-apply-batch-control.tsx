"use client";

import { useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import type { AdminAssuranceLevel, AdminRole } from "@confluendo/ingestion-platform/admin-auth";
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

type Decision =
  | { state: "idle" }
  | { state: "loading_preflight" }
  | { state: "running" }
  | {
      state: "applied";
      appliedPackageIds: string[];
      skippedAppliedPackageIds: string[];
      auditIds: string[];
    }
  | { state: "blocked"; blocks: string[] }
  | { state: "error"; message: string };

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
  already_applied: "Package has already been applied."
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
  const [decision, setDecision] = useState<Decision>({ state: "idle" });
  const inFlightRef = useRef(false);
  const router = useRouter();
  const pending = decision.state === "running";
  const disabledReason = disabledReasonFor(context, eligibleItems.length);

  useEffect(() => {
    if (disabledReason || selectedPackageIds.length === 0) {
      return;
    }
    let cancelled = false;
    setDecision({ state: "loading_preflight" });
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
        if (cancelled) return;
        if (!payload?.ok) {
          setPreflight(null);
          setPreflightBlocks(payload?.blocks?.map((block) => block.code) ?? ["preflight_failed"]);
          setDecision({ state: "idle" });
          return;
        }
        setPreflight(payload);
        setPreflightBlocks([]);
        setDecision({ state: "idle" });
      } catch {
        if (!cancelled) {
          setPreflight(null);
          setPreflightBlocks(["preflight_failed"]);
          setDecision({ state: "idle" });
        }
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [disabledReason, projectKey, selectedPackageIds, waveKey]);

  if (eligibleItems.length === 0) {
    return null;
  }

  return (
    <div className="admin-canary-control admin-batch-wave-approval-control">
      <p className="admin-kicker">IP-18.8.4 · batch apply to Vamo</p>
      <h3>Apply selected packages to Vamo</h3>
      <p className="admin-canary-note">
        Applies delivered inbox packages sequentially through the existing consumer-owned apply
        function. Stops on first failure. Already-applied packages are skipped.
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

      <label className="admin-canary-reason">
        <span>Audit reason</span>
        <textarea
          value={reason}
          onChange={(event) => setReason(event.target.value)}
          rows={2}
          maxLength={280}
          placeholder="Why apply these delivered packages to Vamo now?"
          disabled={Boolean(disabledReason) || pending}
        />
      </label>

      <div className="admin-action-row">
        <button
          type="button"
          className="admin-command admin-command-primary admin-stateful-command"
          data-state={pending ? "busy" : disabledReason ? "unavailable" : "ready"}
          onClick={() => void submit()}
          disabled={
            Boolean(disabledReason) ||
            pending ||
            selectedPackageIds.length === 0 ||
            preflightBlocks.length > 0 ||
            !preflight
          }
          title={disabledReason ?? undefined}
        >
          {pending
            ? "Applying packages..."
            : `Apply selected packages to Vamo (${selectedPackageIds.length})`}
        </button>
      </div>

      <DecisionView decision={decision} />
    </div>
  );

  function togglePackage(packageId: string) {
    if (selectedPackageIds.includes(packageId)) {
      setSelectedPackageIds(selectedPackageIds.filter((id) => id !== packageId));
      return;
    }
    setSelectedPackageIds([...selectedPackageIds, packageId]);
  }

  async function submit() {
    if (inFlightRef.current || !reason.trim()) {
      if (!reason.trim()) {
        setDecision({ state: "error", message: "Audit reason is required." });
      }
      return;
    }
    inFlightRef.current = true;
    setDecision({ state: "running" });
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
        })
      });
      const payload = (await response.json().catch(() => null)) as
        | {
            ok: true;
            appliedPackageIds: string[];
            skippedAppliedPackageIds: string[];
            auditIds: string[];
          }
        | { ok: false; blocks?: { code: string }[]; error?: string }
        | null;

      if (!payload?.ok) {
        if (payload?.blocks) {
          const blocks = payload.blocks.map((block) => block.code);
          if (blocks.includes("mfa_required") || blocks.includes("fresh_step_up_required")) {
            window.location.assign(freshStepUpHref);
            return;
          }
          setDecision({ state: "blocked", blocks });
          return;
        }
        setDecision({ state: "error", message: payload?.error ?? "Batch apply failed." });
        return;
      }

      setDecision({
        state: "applied",
        appliedPackageIds: payload.appliedPackageIds,
        skippedAppliedPackageIds: payload.skippedAppliedPackageIds,
        auditIds: payload.auditIds
      });
      router.refresh();
    } catch {
      setDecision({ state: "error", message: "Batch apply request failed to send." });
    } finally {
      inFlightRef.current = false;
    }
  }
}

function DecisionView({ decision }: { decision: Decision }) {
  if (
    decision.state === "idle" ||
    decision.state === "loading_preflight" ||
    decision.state === "running"
  ) {
    return null;
  }
  if (decision.state === "applied") {
    return (
      <div className="admin-command-result admin-command-result-ok" role="status">
        <strong>Batch consumer apply completed</strong>
        <span>Applied {decision.appliedPackageIds.length} package(s)</span>
        {decision.skippedAppliedPackageIds.length > 0 ? (
          <span>Skipped {decision.skippedAppliedPackageIds.length} already-applied package(s)</span>
        ) : null}
        <span>Audit ids: {decision.auditIds.join(", ")}</span>
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

function disabledReasonFor(context: { role: AdminRole; assuranceLevel: AdminAssuranceLevel; source: DashboardSource }, eligibleCount: number): string | undefined {
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
