/**
 * Trusted worker for separately confirmed snapshot activation requests.
 *
 * This worker never acquires from a provider. It only runs the existing
 * verified activation orchestration after an operator-created request.
 */
import {
  claimSnapshotActivationRequest,
  completeSnapshotActivationRequest
} from "./snapshot-activation-request-control.js";
import {
  SNAPSHOT_ACTIVATION_CONFIRMATION_VALUE,
  runSnapshotReleaseActivation
} from "./snapshot-release-activation.js";
import type { SnapshotArtifactStore } from "./snapshot-artifact-store.js";

export const SNAPSHOT_ACTIVATION_WORKER_CONFIRMATION_ENV =
  "CONFIRM_CONFLUENDO_SNAPSHOT_ACTIVATION_WORKER" as const;
export const SNAPSHOT_ACTIVATION_WORKER_CONFIRMATION_VALUE = "YES" as const;

export type SnapshotActivationWorkerResult =
  | { ok: false; blocks: string[] }
  | { ok: true; outcome: "idle"; message: string }
  | { ok: true; outcome: "activated"; requestId: string; releaseId: string; bindingId: string; auditId: string; idempotentReplay: boolean }
  | { ok: true; outcome: "failed"; requestId: string; releaseId: string; errorCode: string; errorMessage: string };

export async function runSnapshotActivationWorker(input: {
  connectionString: string;
  workerId: string;
  workerRunKey: string;
  confirmation?: string;
  artifactStore: SnapshotArtifactStore;
  artifactStoreBaseDir?: string;
}): Promise<SnapshotActivationWorkerResult> {
  if (input.confirmation !== SNAPSHOT_ACTIVATION_WORKER_CONFIRMATION_VALUE) {
    return {
      ok: false,
      blocks: [`Set ${SNAPSHOT_ACTIVATION_WORKER_CONFIRMATION_ENV}=${SNAPSHOT_ACTIVATION_WORKER_CONFIRMATION_VALUE} to execute.`]
    };
  }

  const claimed = await claimSnapshotActivationRequest({
    connectionString: input.connectionString,
    workerId: input.workerId,
    workerRunKey: input.workerRunKey
  });
  if (!claimed.ok) {
    return { ok: true, outcome: "idle", message: "No pending snapshot activation request." };
  }

  const request = claimed.request;
  if (claimed.idempotentReplay && request.status === "activated" && request.bindingId && request.activationAuditId) {
    return {
      ok: true,
      outcome: "activated",
      requestId: request.requestId,
      releaseId: request.releaseId,
      bindingId: request.bindingId,
      auditId: request.activationAuditId,
      idempotentReplay: true
    };
  }
  if (claimed.idempotentReplay && request.status === "failed") {
    return {
      ok: true,
      outcome: "failed",
      requestId: request.requestId,
      releaseId: request.releaseId,
      errorCode: request.errorCode ?? "worker_execution_failed",
      errorMessage: request.errorMessage ?? "Activation worker could not complete the request."
    };
  }

  try {
    const activation = await runSnapshotReleaseActivation({
      preview: false,
      confirmation: SNAPSHOT_ACTIVATION_CONFIRMATION_VALUE,
      projectKey: request.projectKey,
      planKey: request.planKey,
      releaseId: request.releaseId,
      artifactStore: input.artifactStore,
      artifactStoreDir: input.artifactStoreBaseDir,
      connectionString: input.connectionString,
      actor: { type: "worker", id: input.workerId },
      auditReason: request.auditReason
    });

    if (!activation.ok) {
      const completed = await completeSnapshotActivationRequest({
        connectionString: input.connectionString,
        requestId: request.requestId,
        workerRunKey: input.workerRunKey,
        status: "failed",
        errorCode: "activation_blocked",
        errorMessage: "A verified artifact, release, or queue precondition blocked activation."
      });
      return {
        ok: true,
        outcome: "failed",
        requestId: completed.requestId,
        releaseId: request.releaseId,
        errorCode: "activation_blocked",
        errorMessage: "A verified artifact, release, or queue precondition blocked activation."
      };
    }

    if (activation.result.mode !== "execute") {
      throw new Error("Activation worker received an unexpected preview result.");
    }

    await completeSnapshotActivationRequest({
      connectionString: input.connectionString,
      requestId: request.requestId,
      workerRunKey: input.workerRunKey,
      status: "activated",
      bindingId: activation.result.bindingId,
      activationAuditId: activation.result.auditId
    });
    return {
      ok: true,
      outcome: "activated",
      requestId: request.requestId,
      releaseId: request.releaseId,
      bindingId: activation.result.bindingId,
      auditId: activation.result.auditId,
      idempotentReplay: false
    };
  } catch {
    const completed = await completeSnapshotActivationRequest({
      connectionString: input.connectionString,
      requestId: request.requestId,
      workerRunKey: input.workerRunKey,
      status: "failed",
      errorCode: "worker_execution_failed",
      errorMessage: "Activation worker could not complete the request."
    });
    return {
      ok: true,
      outcome: "failed",
      requestId: completed.requestId,
      releaseId: request.releaseId,
      errorCode: "worker_execution_failed",
      errorMessage: "Activation worker could not complete the request."
    };
  }
}
