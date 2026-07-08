"use client";

import { useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import type { AdminAssuranceLevel, AdminRole } from "@confluendo/ingestion-platform/admin-auth";

type DashboardSource = "live" | "sample" | "error";

type ApplyPreflight = {
  packageId: string;
  shipmentStatus: string;
  checksum: string;
  itemCount: number;
  pendingItemCount: number;
  targetTables: string[];
  items: Array<{
    itemKey: string;
    targetTable: string;
    operation: string;
    applyStatus: string;
    applyError: string | null;
  }>;
  latestApplyLogResult: string | null;
  latestApplyLogDetail: string | null;
};

type ApplyResult = {
  packageId: string;
  applied: number;
  skipped: number;
  rejected: number;
  status: string;
  error?: string;
};

type Decision =
  | { state: "idle" }
  | { state: "loading_preflight" }
  | { state: "running" }
  | {
      state: "applied";
      auditId: string;
      applyResult: ApplyResult;
      idempotentReplay: boolean;
    }
  | { state: "blocked"; blocks: string[] }
  | {
      state: "failed";
      message: string;
      applyResult?: ApplyResult;
      applyLog?: { result: string | null; detail: string | null };
      itemErrors?: Array<{ itemKey: string; applyError: string | null }>;
    }
  | { state: "error"; message: string };

const freshStepUpHref =
  "/admin/mfa/challenge?reason=fresh_step_up_required&next=%2Fadmin%2Fingestion";

const blockLabels: Record<string, string> = {
  role_denied: "Requires the ingestion_admin role (admin).",
  scope_denied: "This admin account is not scoped to this ingestion project.",
  mfa_required: "Requires verified MFA step-up (AAL2).",
  fresh_step_up_required: "Requires a fresh MFA step-up.",
  audit_reason_required: "A non-empty audit reason is required.",
  package_id_required: "Package id is required.",
  package_not_found: "Production inbox package was not found.",
  shipment_not_delivered: "Shipment must be production_inbox_delivered with pending items.",
  no_pending_items: "No pending shipment items remain for apply.",
  already_applied: "Package has already been applied by the consumer.",
  apply_not_configured: "Consumer apply database URL is not configured on the server."
};

export function ProductionPackageConsumerApplyControl({
  projectKey,
  packageId,
  unitKey,
  shipmentStatus,
  pendingItemCount,
  context
}: {
  projectKey: string;
  packageId: string;
  unitKey: string;
  shipmentStatus?: string | null;
  pendingItemCount?: number | null;
  context: {
    role: AdminRole;
    assuranceLevel: AdminAssuranceLevel;
    source: DashboardSource;
  };
}) {
  const [reason, setReason] = useState("");
  const [preflight, setPreflight] = useState<ApplyPreflight | null>(null);
  const [preflightBlocks, setPreflightBlocks] = useState<string[]>([]);
  const [decision, setDecision] = useState<Decision>({ state: "idle" });
  const inFlightRef = useRef(false);
  const router = useRouter();
  const pending = decision.state === "running";
  const disabledReason = disabledReasonFor(context, packageId, shipmentStatus, pendingItemCount);

  useEffect(() => {
    if (disabledReason) {
      return;
    }
    let cancelled = false;
    setDecision({ state: "loading_preflight" });
    void (async () => {
      try {
        const response = await fetch(
          `/api/admin/ingestion/production-package-wave/apply/preflight?${new URLSearchParams({
            projectKey,
            packageId
          })}`
        );
        const payload = (await response.json().catch(() => null)) as
          | {
              ok: true;
              preflight: ApplyPreflight;
              eligible: boolean;
              blocks: { code: string }[];
            }
          | { ok: false; error?: string }
          | null;
        if (cancelled) return;
        if (!payload?.ok) {
          setDecision({
            state: "error",
            message: payload?.error ?? "Could not load apply preflight."
          });
          return;
        }
        setPreflight(payload.preflight);
        setPreflightBlocks(payload.blocks.map((block) => block.code));
        setDecision({ state: "idle" });
      } catch {
        if (!cancelled) {
          setDecision({ state: "error", message: "Could not load apply preflight." });
        }
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [projectKey, packageId, disabledReason]);

  return (
    <div className="admin-canary-control admin-consumer-apply-control">
      <p className="admin-kicker">IP-18.6 · consumer apply control</p>
      <h3>Apply delivered package to Vamo</h3>
      <p className="admin-canary-note">
        Invokes Vamo&apos;s <code>apply_confluendo_shipment</code> boundary only. Requires admin +
        verified AAL2 + fresh MFA step-up. No direct product-table writes from Confluendo.
      </p>

      <div className="admin-canary-fields">
        <label>
          <span>Scope</span>
          <input type="text" value={unitKey} readOnly disabled />
        </label>
        <label>
          <span>Package id</span>
          <input type="text" value={packageId} readOnly disabled />
        </label>
      </div>

      {preflight ? <PreflightView preflight={preflight} /> : null}

      <label className="admin-canary-reason">
        <span>Audit reason</span>
        <textarea
          value={reason}
          onChange={(event) => setReason(event.target.value)}
          rows={2}
          maxLength={280}
          placeholder="Why apply this delivered inbox package to Vamo now?"
          disabled={Boolean(disabledReason) || pending || preflightBlocks.length > 0}
        />
      </label>

      <div className="admin-action-row">
        <button
          type="button"
          className="admin-command admin-command-primary admin-stateful-command"
          data-state={pending ? "busy" : disabledReason || preflightBlocks.length > 0 ? "unavailable" : "ready"}
          onClick={() => void submit()}
          disabled={Boolean(disabledReason) || pending || preflightBlocks.length > 0}
          title={disabledReason ?? undefined}
        >
          {pending ? "Applying to Vamo..." : "Apply to Vamo"}
        </button>
        {disabledReason ? (
          <p className="admin-action-status" data-state="unavailable">
            Unavailable: {disabledReason}
          </p>
        ) : preflightBlocks.length > 0 ? (
          <p className="admin-action-status" data-state="unavailable">
            Preflight blocked: {preflightBlocks.map((code) => blockLabels[code] ?? code).join(" ")}
          </p>
        ) : null}
      </div>
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
      const response = await fetch("/api/admin/ingestion/production-package-wave/apply", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          projectKey,
          packageId,
          auditReason: reason.trim()
        })
      });
      const payload = (await response.json().catch(() => null)) as
        | {
            ok: true;
            decision: "applied";
            auditId: string;
            applyResult: ApplyResult;
            idempotentReplay: boolean;
          }
        | {
            ok: false;
            decision?: "blocked" | "failed";
            blocks?: { code: string }[];
            error?: string;
            applyResult?: ApplyResult;
            applyLog?: { result: string | null; detail: string | null };
            itemErrors?: Array<{ itemKey: string; applyError: string | null }>;
          }
        | null;

      if (!payload) {
        setDecision({ state: "error", message: "The apply request failed." });
        return;
      }
      if (payload.ok) {
        setDecision({
          state: "applied",
          auditId: payload.auditId,
          applyResult: payload.applyResult,
          idempotentReplay: payload.idempotentReplay
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
        state: "failed",
        message: payload.error ?? "Consumer apply failed.",
        applyResult: payload.applyResult,
        applyLog: payload.applyLog,
        itemErrors: payload.itemErrors
      });
      router.refresh();
    } catch {
      setDecision({ state: "error", message: "The apply request failed to send." });
    } finally {
      inFlightRef.current = false;
    }
  }
}

function PreflightView({ preflight }: { preflight: ApplyPreflight }) {
  return (
    <div className="admin-command-result" role="status">
      <strong>Apply preflight</strong>
      <span>Shipment status: {preflight.shipmentStatus}</span>
      <span>Checksum: {preflight.checksum}</span>
      <span>
        Items: {preflight.itemCount} total · {preflight.pendingItemCount} pending
      </span>
      <span>Target tables: {preflight.targetTables.join(", ") || "—"}</span>
      <ul>
        {preflight.items.map((item) => (
          <li key={item.itemKey}>
            <code>{item.itemKey}</code> → {item.targetTable} · {item.applyStatus}
            {item.applyError ? ` · ${item.applyError}` : ""}
          </li>
        ))}
      </ul>
    </div>
  );
}

function DecisionView({ decision }: { decision: Decision }) {
  if (
    decision.state === "idle" ||
    decision.state === "running" ||
    decision.state === "loading_preflight"
  ) {
    return null;
  }
  if (decision.state === "applied") {
    return (
      <div className="admin-command-result admin-command-result-ok" role="status">
        <strong>Consumer apply completed</strong>
        <span>
          Status: {decision.applyResult.status} · applied={decision.applyResult.applied} · skipped=
          {decision.applyResult.skipped} · rejected={decision.applyResult.rejected}
        </span>
        <span>Audit id: {decision.auditId}</span>
        {decision.idempotentReplay ? <span>Idempotent replay — package was already applied.</span> : null}
      </div>
    );
  }
  if (decision.state === "blocked") {
    return (
      <div className="admin-command-result admin-command-result-error" role="alert">
        <strong>Consumer apply blocked</strong>
        <ul>
          {decision.blocks.map((code) => (
            <li key={code}>{blockLabels[code] ?? code}</li>
          ))}
        </ul>
      </div>
    );
  }
  if (decision.state === "failed") {
    return (
      <div className="admin-command-result admin-command-result-error" role="alert">
        <strong>{decision.message}</strong>
        {decision.applyResult ? (
          <span>
            Result: {decision.applyResult.status} · applied={decision.applyResult.applied} · rejected=
            {decision.applyResult.rejected}
          </span>
        ) : null}
        {decision.applyLog?.detail ? <span>Apply log: {decision.applyLog.detail}</span> : null}
        {decision.itemErrors && decision.itemErrors.length > 0 ? (
          <ul>
            {decision.itemErrors.map((item) => (
              <li key={item.itemKey}>
                <code>{item.itemKey}</code>: {item.applyError}
              </li>
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

function disabledReasonFor(
  context: { role: AdminRole; assuranceLevel: AdminAssuranceLevel; source: DashboardSource },
  packageId: string,
  shipmentStatus?: string | null,
  pendingItemCount?: number | null
): string | undefined {
  if (!packageId) {
    return "No delivered package id is available for consumer apply.";
  }
  if (context.source === "error") {
    return "Live batch queue read failed; consumer apply is disabled.";
  }
  if (context.source !== "live") {
    return "Consumer apply requires a live control plane.";
  }
  if (context.role !== "admin") {
    return "Consumer apply requires the admin role.";
  }
  if (context.assuranceLevel !== "aal2") {
    return "Consumer apply requires verified MFA step-up (AAL2).";
  }
  if (
    shipmentStatus &&
    shipmentStatus !== "production_inbox_delivered" &&
    shipmentStatus !== "consumer_apply_pending"
  ) {
    if (shipmentStatus === "consumer_applied") {
      return "Package has already been applied by the consumer.";
    }
    return `Shipment status ${shipmentStatus} is not eligible for apply.`;
  }
  if (pendingItemCount === 0) {
    return "No pending shipment items remain for consumer apply.";
  }
  return undefined;
}
