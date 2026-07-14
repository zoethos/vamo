/**
 * Pure snapshot artifact key validation (IP-18.8.12).
 */

import {
  SNAPSHOT_ARTIFACT_BUNDLE_FILES,
  type SnapshotArtifactBundleFileName
} from "./snapshot-artifact-bundle.js";

export function assertArtifactKeySafe(artifactKey: string): boolean {
  const trimmed = artifactKey.trim();
  if (!trimmed || trimmed.startsWith("/") || trimmed.includes("\\")) {
    return false;
  }
  const segments = trimmed.split("/").filter((segment) => segment.length > 0);
  if (segments.length < 3) {
    return false;
  }
  return segments.every(
    (segment) => segment !== "." && segment !== ".." && !segment.includes("..")
  );
}

export function objectKeyForArtifactBundleFile(
  artifactKey: string,
  fileName: SnapshotArtifactBundleFileName
): string {
  const normalizedKey = artifactKey.replace(/\/+$/, "");
  if (!SNAPSHOT_ARTIFACT_BUNDLE_FILES.includes(fileName)) {
    throw new Error(`Unsupported snapshot artifact file "${fileName}".`);
  }
  return `${normalizedKey}/${fileName}`;
}
