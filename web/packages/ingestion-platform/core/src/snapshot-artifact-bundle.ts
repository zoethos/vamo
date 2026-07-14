/**
 * Shared snapshot artifact bundle constants (IP-18.8.10 / IP-18.8.12).
 */

import type { SnapshotIntakeArtifacts } from "./versioned-snapshot-intake.js";

export const SNAPSHOT_ARTIFACT_BUNDLE_FILES = [
  "source.jsonl",
  "release.json",
  "coverage-report.json"
] as const;

export type SnapshotArtifactBundleFileName = (typeof SNAPSHOT_ARTIFACT_BUNDLE_FILES)[number];

export function readSnapshotArtifactField(
  artifacts: SnapshotIntakeArtifacts,
  fileName: SnapshotArtifactBundleFileName
): string {
  if (fileName === "source.jsonl") {
    return artifacts.sourceJsonl;
  }
  if (fileName === "release.json") {
    return artifacts.releaseJson;
  }
  return artifacts.coverageReportJson;
}
