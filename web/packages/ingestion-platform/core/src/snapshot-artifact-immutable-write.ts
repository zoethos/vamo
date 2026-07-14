/**
 * Idempotent immutable artifact file writes (IP-18.8.12 remediation).
 */

import { SnapshotArtifactStorageError } from "./snapshot-artifact-storage-error.js";

export async function writeImmutableArtifactContent(input: {
  expectedContent: string;
  readExisting: () => Promise<string | null>;
  writeIfAbsent: (content: string) => Promise<void>;
}): Promise<void> {
  const existing = await input.readExisting();
  if (existing !== null) {
    if (existing !== input.expectedContent) {
      throw new SnapshotArtifactStorageError(
        "artifact_bundle_conflict",
        "Existing artifact content conflicts with the expected bundle file."
      );
    }
    return;
  }

  try {
    await input.writeIfAbsent(input.expectedContent);
  } catch (error) {
    const reread = await input.readExisting();
    if (reread === input.expectedContent) {
      return;
    }
    if (reread !== null) {
      throw new SnapshotArtifactStorageError(
        "artifact_bundle_conflict",
        "Concurrent artifact write produced conflicting content.",
        { cause: error }
      );
    }
    throw error;
  }
}
