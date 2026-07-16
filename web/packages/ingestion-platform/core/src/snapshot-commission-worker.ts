/**
 * Trusted worker orchestration for snapshot release commissioning (IP-18.8.13).
 *
 * Claims one control-plane request and invokes existing FSQ acquisition only.
 * Never activates a release automatically.
 */

import type { SnapshotArtifactStore } from "./snapshot-artifact-store.js";
import {
  claimSnapshotCommissionRequest,
  completeSnapshotCommissionRequest,
  findSnapshotReleaseIdForCommissionRequest,
  loadSnapshotCommissionPlanContext,
  type SnapshotCommissionPgClientLike
} from "./snapshot-commission-control.js";
import {
  snapshotCommissionFailureCodeForAcquisitionBlocks,
  snapshotCommissionOperatorErrorForCode
} from "./snapshot-commission-errors.js";
import { validateFsqPortalAccessTokenExpiry } from "./fsq-portal-access-token.js";
import { runFsqSnapshotAcquire, FSQ_SNAPSHOT_ACQUIRE_CONFIRMATION_VALUE } from "./fsq-snapshot-acquire.js";

export const SNAPSHOT_COMMISSION_WORKER_CONFIRMATION_ENV =
  "CONFIRM_CONFLUENDO_SNAPSHOT_COMMISSION_WORKER" as const;
export const SNAPSHOT_COMMISSION_WORKER_CONFIRMATION_VALUE = "YES" as const;

export interface RunSnapshotCommissionWorkerInput {
  connectionString: string;
  workerId: string;
  workerRunKey: string;
  confirmation?: string;
  portalAccessToken?: string;
  portalAccessTokenExpiresAt?: string;
  artifactStore?: SnapshotArtifactStore;
  artifactStoreBaseDir?: string;
  client?: SnapshotCommissionPgClientLike;
  now?: string;
  duckDbRunner?: import("../../adapters/source/src/fsq-os-places-portal-iceberg-acquire.js").FsqPortalIcebergDuckDbRunner;
  /** Test seam: override acquisition execution. */
  runAcquire?: typeof runFsqSnapshotAcquire;
}

export type RunSnapshotCommissionWorkerResult =
  | { ok: true; outcome: "idle"; message: string }
  | {
      ok: true;
      outcome: "completed" | "idempotent_replay" | "reconciled";
      requestId: string;
      registeredReleaseId: string;
      releaseStatus: "activation_pending";
    }
  | {
      ok: true;
      outcome: "pending_retry";
      requestId: string;
      registeredReleaseId?: string;
      errorCode: "completion_update_failed";
      errorMessage: string;
    }
  | {
      ok: true;
      outcome: "failed";
      requestId: string;
      errorCode: string;
      errorMessage: string;
    }
  | { ok: false; blocks: string[] };

export async function runSnapshotCommissionWorker(
  input: RunSnapshotCommissionWorkerInput
): Promise<RunSnapshotCommissionWorkerResult> {
  if (input.confirmation !== SNAPSHOT_COMMISSION_WORKER_CONFIRMATION_VALUE) {
    return { ok: false, blocks: ["worker_confirmation_missing"] };
  }
  if (!input.portalAccessToken?.trim()) {
    return { ok: false, blocks: ["portal_access_token_missing"] };
  }
  const expiry = validateFsqPortalAccessTokenExpiry({
    expiresAt: input.portalAccessTokenExpiresAt,
    now: input.now
  });
  if (!expiry.ok) {
    return { ok: false, blocks: [expiry.block] };
  }

  const claimed = await claimSnapshotCommissionRequest({
    connectionString: input.connectionString,
    client: input.client,
    workerId: input.workerId,
    workerRunKey: input.workerRunKey
  });

  if (!claimed.ok) {
    return { ok: true, outcome: "idle", message: "No pending snapshot commission request." };
  }

  const request = claimed.request;
  if (claimed.idempotentReplay && request.status === "activation_pending" && request.registeredReleaseId) {
    return {
      ok: true,
      outcome: "idempotent_replay",
      requestId: request.requestId,
      registeredReleaseId: request.registeredReleaseId,
      releaseStatus: "activation_pending"
    };
  }

  const reconciledReleaseId = await resolveRegisteredReleaseId(input, request);
  if (reconciledReleaseId) {
    const finalized = await finalizeCommissionRequest(input, request.requestId, reconciledReleaseId, {
      currentStatus: request.status
    });
    if (finalized.ok) {
      return {
        ok: true,
        outcome: claimed.idempotentReplay ? "idempotent_replay" : "reconciled",
        requestId: request.requestId,
        registeredReleaseId: reconciledReleaseId,
        releaseStatus: "activation_pending"
      };
    }
    console.error("Snapshot commission reconciliation finalize failed", finalized.error);
    return pendingRetryResult(request.requestId, reconciledReleaseId);
  }

  if (claimed.idempotentReplay) {
    return {
      ok: true,
      outcome: "idle",
      message: "Commission request is already claimed by this worker run."
    };
  }

  const planContext = await loadSnapshotCommissionPlanContext({
    connectionString: input.connectionString,
    client: input.client,
    projectKey: request.projectKey,
    planKey: request.planKey
  });
  if (!planContext?.sourceTaxonomy) {
    await failRequest(input, request.requestId, "source_mapping_requires_plan_refresh");
    return failedResult(request.requestId, "source_mapping_requires_plan_refresh");
  }

  const runAcquire = input.runAcquire ?? runFsqSnapshotAcquire;

  try {
    const acquired = await runAcquire({
      countries: request.countries,
      categories: request.categories,
      maxRowsPerScope: request.maxRowsPerScope,
      preview: false,
      confirmation: FSQ_SNAPSHOT_ACQUIRE_CONFIRMATION_VALUE,
      portalAccessToken: input.portalAccessToken,
      portalAccessTokenExpiresAt: input.portalAccessTokenExpiresAt,
      sourceTaxonomy: planContext.sourceTaxonomy,
      duckDbRunner: input.duckDbRunner,
      artifactStore: input.artifactStore,
      artifactStoreBaseDir: input.artifactStoreBaseDir,
      projectKey: request.projectKey,
      controlConnectionString: input.connectionString,
      actor: { type: "worker", id: input.workerId },
      auditReason: `IP-18.8.13 snapshot commission worker for request ${request.requestId}.`,
      commissionRequestId: request.requestId,
      now: input.now
    });

    if (!acquired.ok) {
      const errorCode = snapshotCommissionFailureCodeForAcquisitionBlocks(acquired.blocks);
      await failRequest(input, request.requestId, errorCode);
      return failedResult(request.requestId, errorCode);
    }

    const result = acquired.result;
    if (result.mode !== "execute" || !result.accepted) {
      await failRequest(input, request.requestId, "acquisition_rejected");
      return failedResult(request.requestId, "acquisition_rejected");
    }

    const finalized = await finalizeCommissionRequest(input, request.requestId, result.releaseId, {
      currentStatus: "running"
    });
    if (!finalized.ok) {
      console.error(
        "Snapshot commission completion update failed after release registration",
        finalized.error
      );
      return pendingRetryResult(request.requestId, result.releaseId);
    }

    return {
      ok: true,
      outcome: "completed",
      requestId: request.requestId,
      registeredReleaseId: result.releaseId,
      releaseStatus: "activation_pending"
    };
  } catch (error) {
    console.error("Snapshot commission worker acquisition failed", error);
    await failRequest(input, request.requestId, "worker_execution_failed");
    return failedResult(request.requestId, "worker_execution_failed");
  }
}

async function resolveRegisteredReleaseId(
  input: RunSnapshotCommissionWorkerInput,
  request: { requestId: string; projectKey: string; registeredReleaseId?: string }
): Promise<string | null> {
  if (request.registeredReleaseId) {
    return request.registeredReleaseId;
  }
  return findSnapshotReleaseIdForCommissionRequest({
    connectionString: input.connectionString,
    client: input.client,
    projectKey: request.projectKey,
    requestId: request.requestId
  });
}

async function finalizeCommissionRequest(
  input: RunSnapshotCommissionWorkerInput,
  requestId: string,
  registeredReleaseId: string,
  state: { currentStatus: string }
): Promise<{ ok: true } | { ok: false; error: unknown }> {
  try {
    if (state.currentStatus === "running") {
      await completeSnapshotCommissionRequest({
        connectionString: input.connectionString,
        client: input.client,
        requestId,
        workerRunKey: input.workerRunKey,
        status: "release_registered",
        registeredReleaseId
      });
    }

    await completeSnapshotCommissionRequest({
      connectionString: input.connectionString,
      client: input.client,
      requestId,
      workerRunKey: input.workerRunKey,
      status: "activation_pending",
      registeredReleaseId
    });
    return { ok: true };
  } catch (error) {
    return { ok: false, error };
  }
}

function pendingRetryResult(
  requestId: string,
  registeredReleaseId?: string
): Extract<RunSnapshotCommissionWorkerResult, { outcome: "pending_retry" }> {
  return {
    ok: true,
    outcome: "pending_retry",
    requestId,
    registeredReleaseId,
    errorCode: "completion_update_failed",
    errorMessage: snapshotCommissionOperatorErrorForCode("completion_update_failed")
  };
}

function failedResult(
  requestId: string,
  errorCode: string
): Extract<RunSnapshotCommissionWorkerResult, { outcome: "failed" }> {
  return {
    ok: true,
    outcome: "failed",
    requestId,
    errorCode,
    errorMessage: snapshotCommissionOperatorErrorForCode(errorCode)
  };
}

async function failRequest(
  input: RunSnapshotCommissionWorkerInput,
  requestId: string,
  errorCode: string
): Promise<void> {
  try {
    await completeSnapshotCommissionRequest({
      connectionString: input.connectionString,
      client: input.client,
      requestId,
      workerRunKey: input.workerRunKey,
      status: "failed",
      errorCode,
      errorMessage: snapshotCommissionOperatorErrorForCode(errorCode)
    });
  } catch (error) {
    console.error("Snapshot commission failure update failed", error);
  }
}
