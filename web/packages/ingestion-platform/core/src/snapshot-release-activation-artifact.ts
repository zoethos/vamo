/**
 * Trusted snapshot artifact verification for IP-18.8.11 / IP-18.8.12.
 */

import { resolve, sep } from "node:path";

import type { BatchPlanSpec } from "./batch-plan-spec.js";
import { assertArtifactKeySafe } from "./snapshot-artifact-key.js";
import type { SourceAcquisitionReleaseRecord } from "./source-acquisition-contract.js";
import {
  computeSnapshotArtifactBundleSha256,
  createLocalSnapshotArtifactStore,
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
    | "coverage"
  >;
  plan: Pick<BatchPlanSpec, "projectKey" | "sourceKey" | "targetKey">;
  artifactStoreDir?: string;
  /** Present after activation; binds the entire immutable artifact bundle. */
  expectedBundleSha256?: string;
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

  if (!assertArtifactKeySafe(input.release.artifactKey)) {
    return { ok: false, blocks: ["artifact_key_unsafe"] };
  }

  if (
    input.artifactStoreDir &&
    !assertArtifactKeyUnderStore(input.release.artifactKey, input.artifactStoreDir)
  ) {
    return { ok: false, blocks: ["artifact_key_outside_store"] };
  }

  const store =
    input.artifactStore ??
    (input.artifactStoreDir
      ? createLocalSnapshotArtifactStore(resolve(input.artifactStoreDir))
      : null);
  if (!store) {
    return { ok: false, blocks: ["artifact_store_unconfigured"] };
  }

  let artifacts: SnapshotIntakeArtifacts;
  try {
    artifacts = await store.readReleaseBundle({ artifactKey: input.release.artifactKey });
  } catch {
    return { ok: false, blocks: ["artifact_bundle_missing"] };
  }

  const bundleSha256 = computeSnapshotArtifactBundleSha256(artifacts);
  if (
    input.expectedBundleSha256 &&
    bundleSha256 !== input.expectedBundleSha256
  ) {
    return { ok: false, blocks: ["artifact_bundle_checksum_mismatch"] };
  }

  let releaseJson: Record<string, unknown>;
  let coverageReport: Record<string, unknown>;
  let rows: BatchSnapshotSourceRow[];
  try {
    releaseJson = readJsonObject(artifacts.releaseJson);
    coverageReport = readJsonObject(artifacts.coverageReportJson);
    rows = parseSnapshotSourceRows(artifacts.sourceJsonl);
  } catch {
    return { ok: false, blocks: ["artifact_metadata_invalid"] };
  }

  if (releaseJson.releaseId !== input.release.releaseId) {
    return { ok: false, blocks: ["release_json_release_id_mismatch"] };
  }
  if (releaseJson.outputSha256 !== input.release.outputSha256) {
    return { ok: false, blocks: ["release_json_output_sha256_mismatch"] };
  }
  if (releaseJson.sourceKey !== input.release.sourceKey) {
    return { ok: false, blocks: ["release_json_source_key_mismatch"] };
  }
  if (releaseJson.intendedConsumer !== input.release.intendedConsumer) {
    return { ok: false, blocks: ["release_json_consumer_mismatch"] };
  }
  if (releaseJson.intendedTarget !== input.release.intendedTarget) {
    return { ok: false, blocks: ["release_json_target_mismatch"] };
  }
  if (coverageReport.releaseId !== input.release.releaseId) {
    return { ok: false, blocks: ["coverage_release_id_mismatch"] };
  }
  if (
    coverageReport.validRowCount !== input.release.coverage.validRowCount ||
    coverageReport.invalidRowCount !== input.release.coverage.invalidRowCount ||
    coverageReport.duplicateRowCount !== input.release.coverage.duplicateRowCount ||
    coverageReport.outOfScopeRowCount !== input.release.coverage.outOfScopeRowCount
  ) {
    return { ok: false, blocks: ["coverage_report_mismatch"] };
  }

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

function readJsonObject(value: string): Record<string, unknown> {
  const parsed = JSON.parse(value);
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error("Expected a JSON object.");
  }
  return parsed as Record<string, unknown>;
}
