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
  type SnapshotCommissionPgClientLike
} from "./snapshot-commission-control.js";
import { runFsqSnapshotAcquire, FSQ_SNAPSHOT_ACQUIRE_CONFIRMATION_VALUE } from "./fsq-snapshot-acquire.js";

export const SNAPSHOT_COMMISSION_WORKER_CONFIRMATION_ENV =
  "CONFIRM_CONFLUENDO_SNAPSHOT_COMMISSION_WORKER" as const;
export const SNAPSHOT_COMMISSION_WORKER_CONFIRMATION_VALUE = "YES" as const;

export interface RunSnapshotCommissionWorkerInput {
  connectionString: string;
  workerId: string;
  workerRunKey: string;
  confirmation?: string;
  catalogToken?: string;
  artifactStore?: SnapshotArtifactStore;
  artifactStoreBaseDir?: string;
  client?: SnapshotCommissionPgClientLike;
  now?: string;
  /** Test seam: override acquisition execution. */
  runAcquire?: typeof runFsqSnapshotAcquire;
}

export type RunSnapshotCommissionWorkerResult =
  | { ok: true; outcome: "idle"; message: string }
  | {
      ok: true;
      outcome: "completed" | "idempotent_replay";
      requestId: string;
      registeredReleaseId: string;
      releaseStatus: "activation_pending";
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
  if (!input.catalogToken?.trim()) {
    return { ok: false, blocks: ["catalog_token_missing"] };
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
  if (
    claimed.idempotentReplay &&
    request.status === "activation_pending" &&
    request.registeredReleaseId
  ) {
    return {
      ok: true,
      outcome: "idempotent_replay",
      requestId: request.requestId,
      registeredReleaseId: request.registeredReleaseId,
      releaseStatus: "activation_pending"
    };
  }

  if (claimed.idempotentReplay && request.status === "release_registered" && request.registeredReleaseId) {
    await completeSnapshotCommissionRequest({
      connectionString: input.connectionString,
      client: input.client,
      requestId: request.requestId,
      workerRunKey: input.workerRunKey,
      status: "activation_pending",
      registeredReleaseId: request.registeredReleaseId
    });
    return {
      ok: true,
      outcome: "idempotent_replay",
      requestId: request.requestId,
      registeredReleaseId: request.registeredReleaseId,
      releaseStatus: "activation_pending"
    };
  }

  const runAcquire = input.runAcquire ?? runFsqSnapshotAcquire;

  try {
    const acquired = await runAcquire({
      countries: request.countries,
      categories: request.categories,
      maxRowsPerScope: request.maxRowsPerScope,
      preview: false,
      confirmation: FSQ_SNAPSHOT_ACQUIRE_CONFIRMATION_VALUE,
      catalogToken: input.catalogToken,
      artifactStore: input.artifactStore,
      artifactStoreBaseDir: input.artifactStoreBaseDir,
      projectKey: request.projectKey,
      controlConnectionString: input.connectionString,
      actor: { type: "worker", id: input.workerId },
      auditReason: `IP-18.8.13 snapshot commission worker for request ${request.requestId}.`,
      now: input.now
    });

    if (!acquired.ok) {
      await failRequest(input, request.requestId, "acquisition_blocked", acquired.blocks.join(", "));
      return {
        ok: true,
        outcome: "failed",
        requestId: request.requestId,
        errorCode: "acquisition_blocked",
        errorMessage: "Acquisition was blocked by policy or bounds checks."
      };
    }

    const result = acquired.result;
    if (result.mode !== "execute" || !result.accepted) {
      const blocks =
        result.mode === "execute" && !result.accepted ? result.blocks.join(", ") : "acquisition_rejected";
      await failRequest(input, request.requestId, "acquisition_rejected", blocks);
      return {
        ok: true,
        outcome: "failed",
        requestId: request.requestId,
        errorCode: "acquisition_rejected",
        errorMessage: "Acquisition completed without an accepted release."
      };
    }

    await completeSnapshotCommissionRequest({
      connectionString: input.connectionString,
      client: input.client,
      requestId: request.requestId,
      workerRunKey: input.workerRunKey,
      status: "release_registered",
      registeredReleaseId: result.releaseId
    });

    await completeSnapshotCommissionRequest({
      connectionString: input.connectionString,
      client: input.client,
      requestId: request.requestId,
      workerRunKey: input.workerRunKey,
      status: "activation_pending",
      registeredReleaseId: result.releaseId
    });

    return {
      ok: true,
      outcome: "completed",
      requestId: request.requestId,
      registeredReleaseId: result.releaseId,
      releaseStatus: "activation_pending"
    };
  } catch (error) {
    const message =
      error instanceof Error ? error.message : "Snapshot commission worker failed unexpectedly.";
    await failRequest(input, request.requestId, "worker_execution_failed", message);
    return {
      ok: true,
      outcome: "failed",
      requestId: request.requestId,
      errorCode: "worker_execution_failed",
      errorMessage: "Trusted worker execution failed before release registration completed."
    };
  }
}

async function failRequest(
  input: RunSnapshotCommissionWorkerInput,
  requestId: string,
  errorCode: string,
  errorMessage: string
): Promise<void> {
  await completeSnapshotCommissionRequest({
    connectionString: input.connectionString,
    client: input.client,
    requestId,
    workerRunKey: input.workerRunKey,
    status: "failed",
    errorCode,
    errorMessage
  });
}
