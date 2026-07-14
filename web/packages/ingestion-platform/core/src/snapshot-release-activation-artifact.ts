/**
 * Trusted local snapshot artifact verification for IP-18.8.11 activation.
 */

import { resolve, sep } from "node:path";

import type { BatchPlanSpec } from "./batch-plan-spec.js";
import type { SourceAcquisitionReleaseRecord } from "./source-acquisition-contract.js";
import {
  computeSnapshotArtifactBundleSha256,
  createLocalSnapshotArtifactStore,
  verifySnapshotArtifactBundleContents,
  type SnapshotArtifactStore
} from "./snapshot-artifact-store.js";
import type { BatchSnapshotSourceRow } from "./batch-snapshot-supply-preview.js";
import type { SnapshotIntakeArtifacts } from "./versioned-snapshot-intake.js";

export interface SnapshotActivationArtifactIdentity {
  releaseId: string;
  sourceKey: string;
  artifactKey: string;
  bundleSha256: string;
  outputSha256: string;
  intendedConsumer: string;
  intendedTarget: string;
}

export interface VerifySnapshotActivationArtifactInput {
  release: Pick<
    SourceAcquisitionReleaseRecord,
    | "releaseId"
    | "sourceKey"
    | "outputSha256"
    | "intendedConsumer"
    | "intendedTarget"
    | "artifactKey"
  >;
  plan: Pick<BatchPlanSpec, "projectKey" | "sourceKey" | "targetKey">;
  artifactStoreDir: string;
  artifactStore?: SnapshotArtifactStore;
}

export function verifySnapshotActivationArtifactPlanMatch(
  input: Pick<VerifySnapshotActivationArtifactInput, "release" | "plan">
): string[] {
  const blocks: string[] = [];
  if (input.release.sourceKey !== input.plan.sourceKey) {
    blocks.push("release_source_mismatch");
  }
  if (input.release.intendedTarget !== input.plan.targetKey) {
    blocks.push("release_target_mismatch");
  }
  if (input.release.intendedConsumer !== input.plan.projectKey) {
    blocks.push("release_consumer_mismatch");
  }
  return blocks;
}

export async function verifySnapshotActivationArtifact(
  input: VerifySnapshotActivationArtifactInput
): Promise<
  | {
      ok: true;
      identity: SnapshotActivationArtifactIdentity;
      artifacts: SnapshotIntakeArtifacts;
      rows: BatchSnapshotSourceRow[];
    }
  | { ok: false; blocks: string[] }
> {
  const planBlocks = verifySnapshotActivationArtifactPlanMatch(input);
  if (planBlocks.length > 0) {
    return { ok: false, blocks: planBlocks };
  }

  if (!assertArtifactKeyUnderStore(input.release.artifactKey, input.artifactStoreDir)) {
    return { ok: false, blocks: ["artifact_key_outside_store"] };
  }

  const store =
    input.artifactStore ?? createLocalSnapshotArtifactStore(resolve(input.artifactStoreDir));

  let artifacts: SnapshotIntakeArtifacts;
  try {
    artifacts = await store.readReleaseBundle({ artifactKey: input.release.artifactKey });
  } catch {
    return { ok: false, blocks: ["artifact_bundle_missing"] };
  }

  const bundleSha256 = computeSnapshotArtifactBundleSha256(artifacts);
  const bundleVerified = await store.verifyReleaseBundle({
    artifactKey: input.release.artifactKey,
    expectedBundleSha256: bundleSha256
  });
  if (!bundleVerified) {
    return { ok: false, blocks: ["artifact_bundle_checksum_mismatch"] };
  }
  if (!verifySnapshotArtifactBundleContents(artifacts)) {
    return { ok: false, blocks: ["artifact_output_sha256_mismatch"] };
  }

  const releaseJson = JSON.parse(artifacts.releaseJson) as {
    outputSha256?: string;
    sourceKey?: string;
  };
  if (releaseJson.outputSha256 !== input.release.outputSha256) {
    return { ok: false, blocks: ["release_json_output_sha256_mismatch"] };
  }
  if (releaseJson.sourceKey && releaseJson.sourceKey !== input.release.sourceKey) {
    return { ok: false, blocks: ["release_json_source_key_mismatch"] };
  }

  const rows = parseSnapshotSourceRows(artifacts.sourceJsonl);

  return {
    ok: true,
    identity: {
      releaseId: input.release.releaseId,
      sourceKey: input.release.sourceKey,
      artifactKey: input.release.artifactKey,
      bundleSha256,
      outputSha256: input.release.outputSha256,
      intendedConsumer: input.release.intendedConsumer,
      intendedTarget: input.release.intendedTarget
    },
    artifacts,
    rows
  };
}

export function resolveArtifactDirectoryUnderStore(input: {
  artifactStoreDir: string;
  artifactKey: string;
}): string | null {
  const root = resolve(input.artifactStoreDir);
  const candidate = resolve(root, ...input.artifactKey.split("/"));
  if (!candidate.startsWith(root + sep) && candidate !== root) {
    return null;
  }
  const relative = candidate.slice(root.length + 1);
  if (relative.split(/[\\/]/).includes("..")) {
    return null;
  }
  return candidate;
}

export function assertArtifactKeyUnderStore(artifactKey: string, artifactStoreDir: string): boolean {
  return resolveArtifactDirectoryUnderStore({ artifactStoreDir, artifactKey }) !== null;
}

function parseSnapshotSourceRows(sourceJsonl: string): BatchSnapshotSourceRow[] {
  return sourceJsonl
    .split(/\r?\n/)
    .filter((line) => line.trim().length > 0)
    .map((line) => JSON.parse(line) as BatchSnapshotSourceRow);
}
