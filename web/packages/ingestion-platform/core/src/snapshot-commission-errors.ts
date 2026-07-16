/**
 * Safe operator-facing commissioning errors (IP-18.8.13).
 *
 * Detailed provider, storage, and credential errors stay in worker/server logs only.
 */

export const SNAPSHOT_COMMISSION_OPERATOR_ERROR_MESSAGES: Record<string, string> = {
  acquisition_blocked: "Acquisition was blocked by policy or bounds checks.",
  acquisition_rejected: "Acquisition completed without an accepted release.",
  portal_query_failed:
    "FSQ Places Portal query failed before snapshot intake. Check trusted worker TLS and network configuration, then retry.",
  artifact_store_write_failed:
    "Snapshot artifact storage could not write the release bundle. Check the worker credential and bucket access, then retry.",
  artifact_store_verify_failed:
    "Snapshot artifact storage could not verify the release bundle. Check bucket access and retry.",
  artifact_bundle_checksum_mismatch:
    "Snapshot artifact storage returned a bundle that did not match the expected checksum. Retry only after investigating storage integrity.",
  release_registration_failed:
    "Release registration failed in the Confluendo control plane. Check the trusted worker owner connection and registry schema, then retry.",
  worker_execution_failed: "Trusted worker execution failed before release registration completed.",
  completion_update_failed:
    "The release was registered, but commissioning could not finalize. Rerun the trusted worker to continue.",
  commission_request_already_active:
    "An active commissioning request already exists for this batch plan.",
  plan_not_found: "The requested batch plan was not found in the control plane.",
  plan_not_active: "Commissioning requires an active batch plan.",
  unsupported_source_key: "This batch plan source is not supported for snapshot commissioning.",
  scope_out_of_bounds: "The requested scope is outside approved plan or FSQ bounds.",
  source_plan_mismatch: "The batch plan source does not match the commissioned source contract.",
  commission_plan_context_mismatch:
    "The active autonomy policy and queue workflow disagree on the commissioned batch plan.",
  source_mapping_requires_plan_refresh:
    "Source mapping requires plan refresh. Re-import the active batch plan with sourceTaxonomy before commissioning.",
  portal_access_token_missing:
    "FSQ Places Portal access token is missing from the server/job secret store.",
  portal_access_token_expiry_invalid:
    "FSQ Places Portal token expiry metadata is invalid. Correct the server/job configuration before retrying.",
  portal_access_token_expired:
    "FSQ Places Portal access token has expired. Refresh the server/job secret and retry.",
  portal_access_token_rejected:
    "FSQ Places Portal access token was rejected or has expired. Refresh the server/job secret and retry.",
  portal_query_timeout: "FSQ Places Portal Iceberg query timed out. Retry with a narrower scope."
};

const SNAPSHOT_COMMISSION_ACQUISITION_BLOCK_CODES = new Set([
  "portal_access_token_missing",
  "portal_access_token_expiry_invalid",
  "portal_access_token_expired",
  "portal_access_token_rejected",
  "portal_query_timeout",
  "portal_query_failed",
  "source_mapping_requires_plan_refresh",
  "artifact_store_write_failed",
  "artifact_store_verify_failed",
  "artifact_bundle_checksum_mismatch",
  "release_registration_failed"
]);

/**
 * Carries only an allowlisted, safe failure category from acquisition into the
 * operator-visible commissioning record. Provider and storage error details
 * remain in the trusted worker output.
 */
export function snapshotCommissionFailureCodeForAcquisitionBlocks(
  blocks: readonly string[]
): string {
  return (
    blocks.find((block) => SNAPSHOT_COMMISSION_ACQUISITION_BLOCK_CODES.has(block)) ??
    "acquisition_blocked"
  );
}

const UNSAFE_OPERATOR_FRAGMENT =
  /(?:s3:\/\/|postgres(?:ql)?:\/\/|artifact[_-]?key|fsq[_-]?token|catalog[_-]?token|aws[_-]?|secret|password|Bearer\s+\S+)/i;

export function presentSnapshotCommissionOperatorError(
  errorCode?: string | null,
  storedMessage?: string | null
): string | undefined {
  if (!errorCode?.trim()) {
    return undefined;
  }
  const normalized = SNAPSHOT_COMMISSION_OPERATOR_ERROR_MESSAGES[errorCode] ?? storedMessage;
  if (!normalized) {
    return "Commissioning encountered an error. Inspect trusted worker logs for details.";
  }
  return sanitizeSnapshotCommissionOperatorMessage(normalized);
}

export function sanitizeSnapshotCommissionOperatorMessage(message: string): string {
  const trimmed = message.trim();
  if (!trimmed || UNSAFE_OPERATOR_FRAGMENT.test(trimmed)) {
    return "Commissioning encountered an error. Inspect trusted worker logs for details.";
  }
  return trimmed;
}

export function snapshotCommissionOperatorErrorForCode(code: string): string {
  return (
    SNAPSHOT_COMMISSION_OPERATOR_ERROR_MESSAGES[code] ??
    "Commissioning encountered an error. Inspect trusted worker logs for details."
  );
}
