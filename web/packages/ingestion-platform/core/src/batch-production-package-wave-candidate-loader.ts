import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { parsePipelineSpec, type PipelineSpec } from "../../spec/src/index.js";
import {
  defaultLoadProductionPackageWaveCandidates,
  type BatchProductionPackageWaveDeliveryDeps
} from "./batch-production-package-wave-delivery.js";
import { runFixturePipeline } from "./pipeline-runner.js";
import type { ProductionPackageWaveCandidateLoader } from "./batch-production-package-wave-approval-content.js";

export function resolveDefaultProductionPackagePipelineBundleDir(): string {
  const configured = process.env.INGESTION_PIPELINE_BUNDLE_DIR?.trim();
  if (configured) {
    return configured;
  }
  const here = dirname(fileURLToPath(import.meta.url));
  return resolve(here, "../../fixtures/imported/vamo-place-intelligence");
}

export function loadDefaultProductionPackagePipeline(): {
  bundleDir: string;
  pipeline: PipelineSpec;
} {
  const bundleDir = resolveDefaultProductionPackagePipelineBundleDir();
  const parsed = parsePipelineSpec(readFileSync(resolve(bundleDir, "pipeline.yaml"), "utf8"));
  if (!parsed.ok) {
    throw new Error(
      `Default production package pipeline did not parse: ${JSON.stringify(parsed.errors)}`
    );
  }
  return { bundleDir, pipeline: parsed.value };
}

export function createDefaultProductionPackageWaveCandidateLoader(): ProductionPackageWaveCandidateLoader {
  const { bundleDir, pipeline } = loadDefaultProductionPackagePipeline();
  const loader: NonNullable<BatchProductionPackageWaveDeliveryDeps["loadCandidates"]> = ({
    unit,
    scope
  }) =>
    defaultLoadProductionPackageWaveCandidates({
      unit,
      scope,
      pipeline,
      fixtureRoot: bundleDir,
      runPipeline: (input) => runFixturePipeline(input)
    });
  return loader;
}
