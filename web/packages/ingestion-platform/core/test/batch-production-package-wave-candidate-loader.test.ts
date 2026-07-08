import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { loadDefaultProductionPackagePipeline } from "../src/batch-production-package-wave-candidate-loader.js";

describe("production package-wave candidate loader", () => {
  it("loads the bundled Vamo pipeline from compiled code without an env override", () => {
    const previous = process.env.INGESTION_PIPELINE_BUNDLE_DIR;
    delete process.env.INGESTION_PIPELINE_BUNDLE_DIR;
    try {
      const loaded = loadDefaultProductionPackagePipeline();
      assert.match(
        loaded.bundleDir,
        /fixtures[\\/]imported[\\/]vamo-place-intelligence$/
      );
      assert.equal(loaded.pipeline.name, "Vamo Place Intelligence");
    } finally {
      if (previous === undefined) {
        delete process.env.INGESTION_PIPELINE_BUNDLE_DIR;
      } else {
        process.env.INGESTION_PIPELINE_BUNDLE_DIR = previous;
      }
    }
  });
});
