import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";

import {
  parseConsumerContractManifest,
  parsePipelineSpec,
  parseTargetProjectSpec
} from "../../spec/src/index.js";
import { runFixturePipeline } from "../src/index.js";

const bundleDir = "fixtures/imported/vamo-place-intelligence";

function read(relativePath: string): string {
  return readFileSync(`${bundleDir}/${relativePath}`, "utf8");
}

describe("imported vamo consumer contract", () => {
  it("imports a manifest the platform spec kernel accepts", () => {
    const manifest = parseConsumerContractManifest(read("manifest.yaml"));

    assert.equal(manifest.ok, true);
    if (manifest.ok) {
      assert.equal(manifest.value.consumer, "vamo");
      assert.equal(manifest.value.profile, "place-intelligence");
      assert.equal(manifest.value.exports.pipeline, "pipeline.yaml");
      assert.equal(manifest.value.exports.target, "target.yaml");
    }
  });

  it("validates the imported pipeline and target with IP-01", () => {
    const pipeline = parsePipelineSpec(read("pipeline.yaml"));
    const target = parseTargetProjectSpec(read("target.yaml"));

    assert.equal(pipeline.ok, true);
    assert.equal(target.ok, true);
    if (target.ok) {
      assert.equal(target.value.security.writeMode, "dry_run");
      assert.equal(target.value.engine.exposeServiceRoleToBrowser, false);
    }
  });

  it("dry-runs the imported fixture through IP-03 against the bundle root", async () => {
    const pipeline = parsePipelineSpec(read("pipeline.yaml"));
    if (!pipeline.ok) {
      throw new Error(`imported pipeline did not parse: ${JSON.stringify(pipeline.errors)}`);
    }

    const result = await runFixturePipeline({
      pipeline: pipeline.value,
      batchSize: 10,
      fixtureRoot: bundleDir
    });

    // rows 1,2,5 stage; row 3 dead-letters for each missing mapped name field;
    // row 4 is policy-blocked (media bytes without storage rights).
    assert.deepEqual(
      result.candidates.map((candidate) => candidate.recordKey),
      ["fsq_colosseum", "fsq_eiffel_tower", "fsq_sagrada_familia"]
    );
    assert.equal(result.deadLetters.length, 2);
    assert.equal(result.deadLetters[0]?.reasonCode, "missing_mapped_field");
    assert.equal(
      result.events.some((event) => event.eventType === "policy_blocked"),
      true
    );
  });

  it("records import provenance the platform can audit", () => {
    const metadata = JSON.parse(read("IMPORT_METADATA.json"));

    assert.equal(metadata.kind, "ingestion.import_metadata");
    assert.equal(metadata.consumer, "vamo");
    assert.equal(metadata.profile, "place-intelligence");
    assert.equal(typeof metadata.source.commit, "string");
    assert.equal(metadata.source.commit.length > 0, true);
    assert.equal(Array.isArray(metadata.files), true);
    assert.equal(metadata.files.length >= 4, true);
    for (const file of metadata.files) {
      assert.equal(typeof file.path, "string");
      assert.match(file.sha256, /^[a-f0-9]{64}$/);
    }
  });
});
