/**
 * Artifact-aware candidate loader for active snapshot release plans (IP-18.8.11 / IP-18.8.12).
 */

import { readFileSync } from "node:fs";
import { resolve } from "node:path";

import { parsePipelineSpec, type PipelineSpec } from "../../spec/src/index.js";
import type { ProductionPackageWaveCandidateLoader } from "./batch-production-package-wave-approval-content.js";
import {
  defaultLoadProductionPackageWaveCandidates,
  type BatchProductionPackageWaveDeliveryDeps
} from "./batch-production-package-wave-delivery.js";
import { runFixturePipeline, runSourcePipeline } from "./pipeline-runner.js";
import { materializeArtifactBundleToScopedDir } from "./snapshot-artifact-materialize.js";
import {
  assertArtifactKeyUnderStore,
  resolveArtifactDirectoryUnderStore,
  verifySnapshotActivationArtifact
} from "./snapshot-release-activation-artifact.js";
import { loadSnapshotReleaseForActivation } from "./snapshot-release-activation-control.js";
import { loadActiveSnapshotReleasePlanBinding } from "./snapshot-release-plan-binding-read.js";
import { resolveDefaultProductionPackagePipelineBundleDir } from "./batch-production-package-wave-candidate-loader.js";
import { createLocalSnapshotArtifactStore, type SnapshotArtifactStore } from "./snapshot-artifact-store.js";

export type SnapshotCandidateLoaderDispose = () => void | Promise<void>;

export interface ResolveSnapshotCandidateLoaderInput {
  controlConnectionString?: string;
  client?: Parameters<typeof loadActiveSnapshotReleasePlanBinding>[0]["client"];
  projectKey: string;
  planKey: string;
  artifactStoreDir?: string;
  artifactStore?: SnapshotArtifactStore;
  pipeline?: PipelineSpec;
}

export interface ResolvedSnapshotCandidateLoader {
  usesActivatedRelease: boolean;
  loader: ProductionPackageWaveCandidateLoader;
  waveLoader: NonNullable<BatchProductionPackageWaveDeliveryDeps["loadCandidates"]>;
  dispose: SnapshotCandidateLoaderDispose;
}

const noopDispose: SnapshotCandidateLoaderDispose = async () => {};

export async function resolveSnapshotCandidateLoader(
  input: ResolveSnapshotCandidateLoaderInput
): Promise<ResolvedSnapshotCandidateLoader> {
  const binding = await loadActiveSnapshotReleasePlanBinding({
    connectionString: input.controlConnectionString,
    client: input.client,
    projectKey: input.projectKey,
    planKey: input.planKey
  });

  const { bundleDir, pipeline } = input.pipeline
    ? { bundleDir: resolveDefaultProductionPackagePipelineBundleDir(), pipeline: input.pipeline }
    : loadBundledPipeline();

  if (!binding) {
    const loader = createBundledLoader(pipeline, bundleDir);
    return { usesActivatedRelease: false, loader, waveLoader: loader, dispose: noopDispose };
  }

  const store =
    input.artifactStore ??
    (input.artifactStoreDir?.trim()
      ? createLocalSnapshotArtifactStore(resolve(input.artifactStoreDir))
      : null);
  if (!store) {
    throw new Error(
      "Active snapshot release binding requires a configured snapshot artifact store — bundled fixture fallback is forbidden."
    );
  }

  const release = await loadSnapshotReleaseForActivation({
    connectionString: input.controlConnectionString,
    client: input.client,
    projectKey: input.projectKey,
    releaseId: binding.releaseId
  });
  if (!release) {
    throw new Error(`Active snapshot release "${binding.releaseId}" was not found in the registry.`);
  }

  const verified = await verifySnapshotActivationArtifact({
    release,
    plan: {
      projectKey: input.projectKey,
      sourceKey: release.sourceKey,
      targetKey: release.intendedTarget
    },
    artifactStore: store,
    artifactStoreDir: input.artifactStoreDir,
    expectedBundleSha256: binding.artifactBundleSha256
  });
  if (!verified.ok) {
    throw new Error(
      `Verified artifact required for active release plan — blocked: ${verified.blocks.join(", ")}`
    );
  }

  const resolvedArtifactDir = await resolveArtifactDirectoryForPipeline({
    store,
    artifactKey: release.artifactKey,
    artifactStoreDir: input.artifactStoreDir
  });

  const artifactLoader = createArtifactLoader(pipeline, resolvedArtifactDir.artifactDir);
  return {
    usesActivatedRelease: true,
    loader: artifactLoader,
    waveLoader: artifactLoader,
    dispose: resolvedArtifactDir.dispose
  };
}

async function resolveArtifactDirectoryForPipeline(input: {
  store: SnapshotArtifactStore;
  artifactKey: string;
  artifactStoreDir?: string;
}): Promise<{ artifactDir: string; dispose: SnapshotCandidateLoaderDispose }> {
  if (
    input.artifactStoreDir?.trim() &&
    assertArtifactKeyUnderStore(input.artifactKey, input.artifactStoreDir)
  ) {
    const artifactDir = resolveArtifactDirectoryUnderStore({
      artifactStoreDir: input.artifactStoreDir,
      artifactKey: input.artifactKey
    });
    if (artifactDir) {
      return { artifactDir, dispose: noopDispose };
    }
  }

  const materialized = await materializeArtifactBundleToScopedDir({
    store: input.store,
    artifactKey: input.artifactKey
  });
  return {
    artifactDir: materialized.artifactDir,
    dispose: materialized.dispose
  };
}

function loadBundledPipeline(): { bundleDir: string; pipeline: PipelineSpec } {
  const bundleDir = resolveDefaultProductionPackagePipelineBundleDir();
  const parsed = parsePipelineSpec(readFileSync(resolve(bundleDir, "pipeline.yaml"), "utf8"));
  if (!parsed.ok) {
    throw new Error(`Bundled pipeline did not parse: ${JSON.stringify(parsed.errors)}`);
  }
  return { bundleDir, pipeline: parsed.value };
}

function createBundledLoader(
  pipeline: PipelineSpec,
  bundleDir: string
): ProductionPackageWaveCandidateLoader {
  return ({ unit, scope }) =>
    defaultLoadProductionPackageWaveCandidates({
      unit,
      scope,
      pipeline,
      fixtureRoot: bundleDir,
      runPipeline: (runInput) => runFixturePipeline(runInput)
    });
}

function createArtifactLoader(
  pipeline: PipelineSpec,
  artifactDir: string
): ProductionPackageWaveCandidateLoader {
  const snapshotPipeline: PipelineSpec = {
    ...pipeline,
    source: {
      ...pipeline.source,
      adapter: "snapshot",
      connection: {
        ...(pipeline.source.connection ?? {}),
        snapshotPath: "source.jsonl",
        format: "jsonl"
      }
    }
  };

  return ({ unit, scope }) =>
    defaultLoadProductionPackageWaveCandidates({
      unit,
      scope,
      pipeline: snapshotPipeline,
      fixtureRoot: artifactDir,
      runPipeline: (runInput) =>
        runSourcePipeline({
          pipeline: snapshotPipeline,
          batchSize: runInput.batchSize,
          sourceRoot: artifactDir
        })
    });
}

export function createWaveUnitCandidateLoader(
  resolved: ResolvedSnapshotCandidateLoader
): ProductionPackageWaveCandidateLoader {
  return ({ unit, scope }) => resolved.waveLoader({ unit, scope });
}
