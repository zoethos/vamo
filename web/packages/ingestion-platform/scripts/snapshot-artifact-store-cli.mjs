#!/usr/bin/env node

import { resolveSnapshotArtifactStoreFromJobEnv } from "../dist/adapters/artifact/src/index.js";

export function hasHostedSnapshotArtifactStoreProfile(env = process.env) {
  const profile = env.CONFLUENDO_SNAPSHOT_ARTIFACT_STORE?.trim()?.toLowerCase();
  return profile === "s3" || profile === "supabase";
}

export async function resolveCliSnapshotArtifactStore(input = {}) {
  const env = input.env ?? process.env;
  const preferLocalDir = input.preferLocalDir?.trim()
    ? input.preferLocalDir
    : undefined;
  const resolved = await resolveSnapshotArtifactStoreFromJobEnv({
    env,
    preferLocalDir,
    requireHostedStore: input.requireHostedStore ?? false
  });
  if (!resolved.ok) {
    return resolved;
  }
  return {
    ok: true,
    config: resolved.config,
    store: resolved.store,
    artifactStoreDir: resolved.config.kind === "local" ? resolved.config.baseDir : undefined
  };
}

export function printArtifactStoreResolutionFailure(resolved) {
  console.error("Snapshot artifact store configuration blocked:");
  for (const block of resolved.blocks) {
    console.error(`  - [${block.code}] ${block.message}`);
  }
}
