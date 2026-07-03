import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";

import { evaluateRecordPolicy, hasPolicyDenial } from "../src/index.js";
import { parsePipelineSpec } from "../../spec/src/index.js";

const parsedPipeline = parsePipelineSpec(
  readFileSync("fixtures/imported/vamo-place-intelligence/pipeline.yaml", "utf8")
);

if (!parsedPipeline.ok) {
  throw new Error(`Fixture pipeline did not parse: ${JSON.stringify(parsedPipeline.errors)}`);
}

const pipeline = parsedPipeline.value;

describe("policy engine", () => {
  it("allows cacheable fact/content rows when source rights permit them", () => {
    const evaluations = evaluateRecordPolicy({
      pipeline,
      record: {
        source: {
          id: "fsq_colosseum",
          name: "Colosseum"
        },
        scope: {
          category: "poi"
        },
        attribution: "FSQ Open Source Places"
      },
      recordKey: "fsq_colosseum"
    });

    assert.equal(hasPolicyDenial(evaluations), false);
    assert.equal(evaluations.every((evaluation) => evaluation.decision === "allow"), true);
  });

  it("denies rows that contain media bytes when media storage is not permitted", () => {
    const evaluations = evaluateRecordPolicy({
      pipeline,
      record: {
        source: {
          id: "fsq_trevi_media",
          name: "Trevi Fountain"
        },
        media: {
          bytesBase64: "AAAA"
        },
        scope: {
          category: "poi"
        }
      },
      recordKey: "fsq_trevi_media"
    });

    assert.equal(hasPolicyDenial(evaluations), true);
    assert.equal(
      evaluations.some((evaluation) => evaluation.reasonCode === "media_bytes_not_cacheable"),
      true
    );
  });

  it("denies rows outside the supported category set", () => {
    const evaluations = evaluateRecordPolicy({
      pipeline,
      record: {
        source: {
          id: "fsq_unsupported_category",
          name: "Unsupported Category"
        },
        scope: {
          category: "nightlife"
        },
        attribution: "FSQ Open Source Places"
      },
      recordKey: "fsq_unsupported_category"
    });

    assert.equal(hasPolicyDenial(evaluations), true);
    assert.equal(
      evaluations.some((evaluation) => evaluation.reasonCode === "value_not_allowed"),
      true
    );
  });
});
