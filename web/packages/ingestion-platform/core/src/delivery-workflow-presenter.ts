export type DeliveryWorkflowStepKey =
  | "staging_verified"
  | "eligible_for_package"
  | "package_approved"
  | "delivered_to_inbox"
  | "apply_pending"
  | "applied"
  | "blocked";

export type DeliveryWorkflowHighlight = DeliveryWorkflowStepKey | "apply_state_unknown";

export const DELIVERY_WORKFLOW_STEPS: ReadonlyArray<{
  key: DeliveryWorkflowStepKey;
  label: string;
}> = [
  { key: "staging_verified", label: "Staging verified" },
  { key: "eligible_for_package", label: "Eligible for package" },
  { key: "package_approved", label: "Package approved" },
  { key: "delivered_to_inbox", label: "Delivered to inbox" },
  { key: "apply_pending", label: "Apply pending" },
  { key: "applied", label: "Applied" },
  { key: "blocked", label: "Blocked" }
] as const;

export const DELIVERY_APPLY_STATE_UNKNOWN_LABEL = "Delivered — apply state unknown";

export const DELIVERY_PAGE_INTRO =
  "Delivery moves staging-verified data into the consumer inbox, then applies it through the consumer-owned apply function. For Vamo, Confluendo can deliver packages to the Vamo production inbox, but Vamo still controls when those packages are applied to product tables.";

export const DELIVERY_COMPACT_INTRO =
  "Use this page to approve, deliver, and apply production packages. Each package starts from staging-verified data, lands in the consumer inbox, then waits for the consumer-owned apply step.";

export const DELIVERY_REFRESH_TELEMETRY_SAFETY =
  "When a package's real state is unclear, refresh delivery telemetry first. It reads the actual consumer inbox, does not change product data, and is safe to run before retrying approval, delivery, or apply.";

export const DELIVERY_PARTIAL_BATCH_APPLY_COPY =
  "Batch apply is sequential, not atomic. If package 3 fails in a 5-package batch, packages 1–2 may already be applied, package 3 failed, and packages 4–5 were not attempted. After fixing the failed package, re-run apply. Re-running apply is safe because the apply function skips packages that are already applied. Do not re-deliver after partial apply failure — refresh telemetry, fix the failed package, then re-run apply.";

export const DELIVERY_LONG_RUNNING_COPY =
  "Applying multiple packages can take time. While apply is running, do not refresh or retry from another tab. The page will refresh delivery telemetry when the request completes.";

export const DELIVERY_APPROVAL_ENVELOPE_EMPTY_COPY =
  "Select eligible scopes to preview the approval envelope.";

export type DeliveryStateTermRow = {
  state: string;
  meaning: string;
  whyItMatters: string;
  operatorAction: string;
};

export const DELIVERY_STATE_TERMINOLOGY: DeliveryStateTermRow[] = [
  {
    state: "Staging verified",
    meaning:
      "The scope was written successfully to the consumer staging target and has valid staging evidence.",
    whyItMatters:
      "This is the proof Confluendo needs before a production package can be prepared.",
    operatorAction:
      "No production action yet. Use it as the source pool for package eligibility."
  },
  {
    state: "Eligible for package",
    meaning:
      "The scope passed dry-run and staging verification, has valid evidence, and can be included in a production package approval.",
    whyItMatters: "This is the pool of work that can move forward.",
    operatorAction:
      "Select one or more eligible scopes, review the approval envelope, enter an audit reason, and request package approval."
  },
  {
    state: "Package approved",
    meaning:
      "An operator approved a bounded production package wave, but delivery to the consumer inbox has not happened yet. Approvals expire after about 15 minutes.",
    whyItMatters:
      "This is a short-lived delivery window, not a completed delivery.",
    operatorAction:
      "Deliver promptly with the confirmation-gated delivery command. If the approval expires, create a fresh approval."
  },
  {
    state: "Delivered to inbox",
    meaning:
      "Confluendo delivered the package to the consumer production inbox. Product tables have not necessarily changed yet.",
    whyItMatters: "Delivery and apply are separate safety boundaries.",
    operatorAction:
      "If the package is not yet applied, run or click the Apply to Vamo control after checking preflight."
  },
  {
    state: "Apply pending",
    meaning: "The package is in the consumer inbox and has pending apply items.",
    whyItMatters: "The package is ready for the consumer-owned apply step.",
    operatorAction:
      "Run apply preflight, confirm target tables/items, enter an audit reason, and apply to Vamo."
  },
  {
    state: DELIVERY_APPLY_STATE_UNKNOWN_LABEL,
    meaning:
      "The package is delivered, but telemetry is unavailable or has not confirmed whether apply is pending, applied, or failed.",
    whyItMatters: "The UI must not claim a pending/apply state it cannot prove.",
    operatorAction:
      "Refresh delivery telemetry before retrying, applying, or escalating."
  },
  {
    state: "Applied",
    meaning:
      "The consumer apply function completed successfully. For Vamo, the package data is now in the Vamo product tables.",
    whyItMatters:
      "This package is done and should not be re-delivered. A completed package should not be re-applied without a recovery reason.",
    operatorAction:
      "No action needed. Use it as evidence for ramp confidence and move to the next eligible package."
  },
  {
    state: "Blocked",
    meaning:
      "A guard stopped the package or one of its items. Common reasons include stale evidence, checksum drift, target incompatibility, expired approval, failed apply, partial-batch apply failure, or a policy limit.",
    whyItMatters: "Blocked work needs investigation before retry.",
    operatorAction:
      "Open details, read the blocker reason, fix the upstream issue, refresh telemetry, then create a fresh approval or rerun the appropriate gated step."
  }
];

export type DeliveryWorkflowGuideInput = {
  latestWaveStatus?: string | null;
  consumerApplyStatus?: string | null;
  applyTelemetrySource?: string;
  eligibleCount: number;
  deliveredCount: number;
  applyPendingCount: number;
  appliedCount: number;
  blockedCount: number;
  hasLatestWave: boolean;
};

export function isDeliveredApplyStateUnknown(input: DeliveryWorkflowGuideInput): boolean {
  if (input.applyTelemetrySource === "inbox") {
    return false;
  }
  const status = normalizeWaveStatus(input.latestWaveStatus);
  if (!isDeliveredWaveStatus(status)) {
    return false;
  }
  if (input.consumerApplyStatus === "applied" || input.consumerApplyStatus === "failed") {
    return false;
  }
  return true;
}

export function resolveDeliveryWorkflowHighlight(
  input: DeliveryWorkflowGuideInput
): DeliveryWorkflowHighlight {
  if (isDeliveredApplyStateUnknown(input)) {
    return "apply_state_unknown";
  }
  if (input.blockedCount > 0 && input.applyPendingCount === 0 && input.eligibleCount === 0) {
    return "blocked";
  }
  if (input.applyPendingCount > 0) {
    return "apply_pending";
  }

  const status = normalizeWaveStatus(input.latestWaveStatus);
  if (status === "consumer_applied" || input.consumerApplyStatus === "applied") {
    return "applied";
  }
  if (status === "consumer_apply_pending") {
    return "apply_pending";
  }
  if (isDeliveredWaveStatus(status)) {
    return "delivered_to_inbox";
  }
  if (
    status === "production_package_approved" ||
    status === "approved" ||
    status === "production_package_delivering" ||
    status === "delivering"
  ) {
    return "package_approved";
  }
  if (input.eligibleCount > 0) {
    return "eligible_for_package";
  }
  if (input.hasLatestWave && input.appliedCount > 0 && input.applyPendingCount === 0) {
    return "applied";
  }
  return "staging_verified";
}

export function buildDeliveryWhatToDoNext(input: DeliveryWorkflowGuideInput): string {
  const highlight = resolveDeliveryWorkflowHighlight(input);
  switch (highlight) {
    case "eligible_for_package":
      return "Select staging-verified scopes, review the derived approval envelope, enter an audit reason, and request package approval.";
    case "package_approved":
      return "Deliver promptly with the confirmation-gated delivery command. Production package approvals expire after about 15 minutes — deliver or create a fresh approval.";
    case "delivered_to_inbox":
    case "apply_pending":
      return "Run apply preflight, confirm pending items and target tables, enter an audit reason, and apply to Vamo.";
    case "apply_state_unknown":
      return "Refresh delivery telemetry before retrying, applying, or escalating. Do not assume apply is still pending.";
    case "applied":
      return "No action needed for completed packages. Continue to the next eligible package wave or review ramp evidence.";
    case "blocked":
      return "Open blocker details, identify whether the fix belongs in source data, staging evidence, package content, credentials, or policy, then refresh telemetry before retrying.";
    default:
      return "A scope becomes eligible only after Confluendo proves the data in dry-run and staging verification. If a scope is missing here, check the Staging tab first.";
  }
}

export function buildDeliveryTerminalStatus(input: DeliveryWorkflowGuideInput): string | null {
  if (!input.hasLatestWave && input.eligibleCount === 0) {
    return null;
  }
  if (input.eligibleCount === 0 && input.applyPendingCount === 0 && input.blockedCount === 0) {
    if (input.appliedCount > 0 || normalizeWaveStatus(input.latestWaveStatus) === "consumer_applied") {
      return "No pending delivery work. Delivery is complete for now.";
    }
  }
  return null;
}

export function deliveryWorkflowStepLabel(highlight: DeliveryWorkflowHighlight): string {
  if (highlight === "apply_state_unknown") {
    return DELIVERY_APPLY_STATE_UNKNOWN_LABEL;
  }
  return DELIVERY_WORKFLOW_STEPS.find((step) => step.key === highlight)?.label ?? "Staging verified";
}

function normalizeWaveStatus(status?: string | null): string {
  return status?.trim() ?? "";
}

function isDeliveredWaveStatus(status: string): boolean {
  return (
    status === "delivered" ||
    status === "production_package_delivered" ||
    status === "consumer_apply_pending"
  );
}
