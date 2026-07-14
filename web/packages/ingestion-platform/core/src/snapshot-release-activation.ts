/**
 * Snapshot release activation orchestrator (IP-18.8.11).
 *
 * Preview is write-free. Execute binds a verified artifact to a batch plan and
 * reconciles queue supply in one control-plane transaction. No provider calls,
 * Vamo writes, inbox delivery, or consumer apply occur here.
 */

import { Client } from "pg";

import { loadBatchQueueSnapshot } from "./batch-queue-control-read.js";
import { persistBatchQueueSnapshot } from "./batch-queue-control.js";
import type { BatchPlanSpec } from "./batch-plan-spec.js";
import { verifySnapshotActivationArtifact } from "./snapshot-release-activation-artifact.js";
import {
  activateSnapshotRelease,
  loadBatchPlanSpecForActivation,
  loadSnapshotReleaseForActivation
} from "./snapshot-release-activation-control.js";
import { reconcileActivatedSnapshotQueue } from "./snapshot-release-activation-reconcile.js";

export const SNAPSHOT_ACTIVATION_CONFIRMATION_ENV =
  "CONFIRM_CONFLUENDO_SNAPSHOT_RELEASE_ACTIVATION" as const;
export const SNAPSHOT_ACTIVATION_CONFIRMATION_VALUE = "YES" as const;

export interface RunSnapshotReleaseActivationInput {
  preview: boolean;
  confirmation?: string;
  projectKey: string;
  planKey: string;
  releaseId: string;
  artifactStoreDir: string;
  connectionString: string;
  actor?: { type: string; id: string };
  auditReason?: string;
}

export interface SnapshotReleaseActivationPreview {
  mode: "preview";
  releaseId: string;
  planKey: string;
  artifactIdentity: {
    artifactKey: string;
    bundleSha256: string;
    outputSha256: string;
  };
  queueChanges: {
    changedUnitKeys: string[];
    supplyReadyCount: number;
    parkedCount: number;
    preservedCount: number;
    totalUnits: number;
  };
  nextAction: string;
}

export interface SnapshotReleaseActivationExecuteResult {
  mode: "execute";
  bindingId: string;
  auditId: string;
  releaseId: string;
  planKey: string;
  queueChanges: SnapshotReleaseActivationPreview["queueChanges"];
}

export type RunSnapshotReleaseActivationResult =
  | { ok: false; blocks: string[] }
  | { ok: true; result: SnapshotReleaseActivationPreview | SnapshotReleaseActivationExecuteResult };

export async function runSnapshotReleaseActivation(
  input: RunSnapshotReleaseActivationInput
): Promise<RunSnapshotReleaseActivationResult> {
  if (!input.connectionString?.trim()) {
    return { ok: false, blocks: ["INGESTION_CONTROL_DATABASE_URL is required."] };
  }

  if (!input.preview) {
    if (input.confirmation !== SNAPSHOT_ACTIVATION_CONFIRMATION_VALUE) {
      return {
        ok: false,
        blocks: [`Set ${SNAPSHOT_ACTIVATION_CONFIRMATION_ENV}=${SNAPSHOT_ACTIVATION_CONFIRMATION_VALUE} to execute.`]
      };
    }
  }

  const release = await loadSnapshotReleaseForActivation({
    connectionString: input.connectionString,
    projectKey: input.projectKey,
    releaseId: input.releaseId
  });
  if (!release) {
    return { ok: false, blocks: ["release_not_found"] };
  }
  if (release.status !== "activation_ready") {
    return { ok: false, blocks: ["release_not_activation_ready"] };
  }

  const planSpecRecord = await loadBatchPlanSpecForActivation({
    connectionString: input.connectionString,
    projectKey: input.projectKey,
    planKey: input.planKey
  });
  if (!planSpecRecord) {
    return { ok: false, blocks: ["batch_plan_not_found"] };
  }
  const planSpec = planSpecRecord as unknown as BatchPlanSpec;

  const currentSnapshot = await loadBatchQueueSnapshot({
    connectionString: input.connectionString,
    projectKey: input.projectKey,
    planKey: input.planKey
  });
  if (!currentSnapshot) {
    return { ok: false, blocks: ["batch_queue_not_found"] };
  }

  const verified = await verifySnapshotActivationArtifact({
    release,
    plan: planSpec,
    artifactStoreDir: input.artifactStoreDir
  });
  if (!verified.ok) {
    return { ok: false, blocks: verified.blocks };
  }

  const reconciled = reconcileActivatedSnapshotQueue({
    currentSnapshot,
    spec: planSpec,
    rows: verified.rows
  });

  const queueChanges = {
    changedUnitKeys: reconciled.changedUnitKeys,
    supplyReadyCount: reconciled.supplyReadyCount,
    parkedCount: reconciled.parkedCount,
    preservedCount: reconciled.preservedCount,
    totalUnits: reconciled.snapshot.progress.total
  };

  if (input.preview) {
    return {
      ok: true,
      result: {
        mode: "preview",
        releaseId: input.releaseId,
        planKey: input.planKey,
        artifactIdentity: {
          artifactKey: verified.identity.artifactKey,
          bundleSha256: verified.identity.bundleSha256,
          outputSha256: verified.identity.outputSha256
        },
        queueChanges,
        nextAction: buildPreviewNextAction(queueChanges)
      }
    };
  }

  const client = new Client({ connectionString: input.connectionString });
  await client.connect();
  try {
    await client.query("begin");
    await client.query("set local statement_timeout = '15s'");

    const activated = await activateSnapshotRelease({
      client,
      projectKey: input.projectKey,
      planKey: input.planKey,
      releaseId: input.releaseId,
      artifactBundleSha256: verified.identity.bundleSha256,
      actor: input.actor ?? { type: "operator", id: "snapshot-activate-cli" },
      auditReason:
        input.auditReason ??
        "Activate verified snapshot release and reconcile batch queue supply."
    });

    await persistBatchQueueSnapshot({
      client,
      projectKey: input.projectKey,
      snapshot: reconciled.snapshot,
      spec: planSpec,
      manageTransaction: false
    });

    await client.query("commit");

    return {
      ok: true,
      result: {
        mode: "execute",
        bindingId: activated.bindingId,
        auditId: activated.auditId,
        releaseId: activated.releaseId,
        planKey: activated.planKey,
        queueChanges
      }
    };
  } catch (error) {
    await client.query("rollback");
    throw error;
  } finally {
    await client.end();
  }
}

function buildPreviewNextAction(
  changes: SnapshotReleaseActivationPreview["queueChanges"]
): string {
  return `Would update ${changes.changedUnitKeys.length} scope(s): ${changes.supplyReadyCount} ready, ${changes.parkedCount} parked, ${changes.preservedCount} preserved in-flight/terminal.`;
}
