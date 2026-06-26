import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { parseConsumerContractManifest } from "../src/index.js";

const validManifest = `
kind: ingestion.consumer_contract
consumer: vamo
profile: place-intelligence
version: 1
title: Vamo Place Intelligence Ingestion Contract
exports:
  pipeline: pipeline.yaml
  target: target.yaml
  fixtures:
    - fixtures/source.jsonl
`;

describe("consumer contract manifest", () => {
  it("parses a valid consumer contract manifest", () => {
    const result = parseConsumerContractManifest(validManifest);

    assert.equal(result.ok, true);
    if (result.ok) {
      assert.equal(result.value.consumer, "vamo");
      assert.equal(result.value.profile, "place-intelligence");
      assert.equal(result.value.version, 1);
      assert.equal(result.value.exports.pipeline, "pipeline.yaml");
      assert.equal(result.value.exports.target, "target.yaml");
      assert.deepEqual(result.value.exports.fixtures, ["fixtures/source.jsonl"]);
      assert.equal(result.value.normalizedSpecVersion, 1);
    }
  });

  it("rejects the wrong kind", () => {
    const result = parseConsumerContractManifest(`
kind: ingestion.pipeline
consumer: vamo
profile: place-intelligence
version: 1
exports:
  pipeline: pipeline.yaml
  target: target.yaml
`);

    assert.equal(result.ok, false);
    if (!result.ok) {
      assert.equal(result.errors.some((error) => error.path === "kind"), true);
    }
  });

  it("reports missing required fields with field paths", () => {
    const result = parseConsumerContractManifest(`
kind: ingestion.consumer_contract
version: 1
exports:
  target: target.yaml
`);

    assert.equal(result.ok, false);
    if (!result.ok) {
      const paths = result.errors.map((error) => error.path);
      assert.equal(paths.includes("consumer"), true);
      assert.equal(paths.includes("profile"), true);
      assert.equal(paths.includes("exports.pipeline"), true);
    }
  });

  it("rejects export paths that escape the bundle", () => {
    const result = parseConsumerContractManifest(`
kind: ingestion.consumer_contract
consumer: vamo
profile: place-intelligence
version: 1
exports:
  pipeline: ../../../etc/passwd
  target: /abs/target.yaml
  fixtures:
    - fixtures/../../secret.jsonl
`);

    assert.equal(result.ok, false);
    if (!result.ok) {
      const unsafe = result.errors.filter(
        (error) =>
          error.code === "invalid_shape" && error.message.includes("traverse upward")
      );
      assert.deepEqual(
        unsafe.map((error) => error.path).sort(),
        ["exports.fixtures[0]", "exports.pipeline", "exports.target"]
      );
    }
  });
});
