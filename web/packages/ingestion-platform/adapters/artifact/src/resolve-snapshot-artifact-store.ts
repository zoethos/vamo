/**
 * Resolve a trusted snapshot artifact store from server/job environment (IP-18.8.12).
 */

import type { SnapshotArtifactStore } from "../../../core/src/snapshot-artifact-store.js";
import { createSnapshotArtifactStore } from "./create-snapshot-artifact-store.js";
import {
  parseSnapshotArtifactStoreConfig,
  type ParseSnapshotArtifactStoreConfigInput,
  type ParseSnapshotArtifactStoreConfigResult,
  type SnapshotArtifactStoreConfig
} from "./snapshot-artifact-store-config.js";

export type ResolveSnapshotArtifactStoreResult =
  | {
      ok: true;
      config: SnapshotArtifactStoreConfig;
      store: SnapshotArtifactStore;
    }
  | ParseSnapshotArtifactStoreConfigResult;

export async function resolveSnapshotArtifactStoreFromJobEnv(
  input: ParseSnapshotArtifactStoreConfigInput
): Promise<ResolveSnapshotArtifactStoreResult> {
  const parsed = parseSnapshotArtifactStoreConfig(input);
  if (!parsed.ok) {
    return parsed;
  }
  const store = await createSnapshotArtifactStore(parsed.config);
  return { ok: true, config: parsed.config, store };
}
