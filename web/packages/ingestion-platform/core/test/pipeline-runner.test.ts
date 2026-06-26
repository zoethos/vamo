import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";

import { mapRecord, runFixturePipeline } from "../src/pipeline-runner.js";
import { parsePipelineSpec } from "../../spec/src/index.js";

const fixtureRoot = "fixtures/imported/vamo-place-intelligence";
const parsedPipeline = parsePipelineSpec(
  readFileSync(`${fixtureRoot}/pipeline.yaml`, "utf8")
);

if (!parsedPipeline.ok) {
  throw new Error(`Fixture pipeline did not parse: ${JSON.stringify(parsedPipeline.errors)}`);
}

const pipeline = parsedPipeline.value;

describe("fixture pipeline runner", () => {
  it("stages candidates, policy evaluations, events, and checkpoint output", async () => {
    const result = await runFixturePipeline({
      pipeline,
      batchSize: 2,
      fixtureRoot
    });

    assert.equal(result.candidates.length, 2);
    assert.equal(result.deadLetters.length, 0);
    assert.equal(result.policyEvaluations.length, 6);
    assert.equal(result.checkpoint.cursorValue.last, 2);
    assert.equal(result.checkpoint.lastRecordKey, "fsq_eiffel_tower");
    assert.equal(
      result.events.some((event) => event.eventType === "checkpoint_committed"),
      true
    );
  });

  it("resumes from checkpoint and advances through dead-lettered and blocked rows", async () => {
    const first = await runFixturePipeline({
      pipeline,
      batchSize: 2,
      fixtureRoot
    });
    const resumed = await runFixturePipeline({
      pipeline,
      batchSize: 10,
      checkpoint: first.checkpoint,
      fixtureRoot
    });

    assert.deepEqual(
      resumed.candidates.map((candidate) => candidate.recordKey),
      ["fsq_sagrada_familia"]
    );
    assert.equal(resumed.deadLetters.length, 1);
    assert.equal(resumed.deadLetters[0]?.reasonCode, "missing_mapped_field");
    assert.equal(
      resumed.events.some((event) => event.eventType === "policy_blocked"),
      true
    );
    assert.equal(resumed.checkpoint.cursorValue.last, 5);
    assert.equal(resumed.checkpoint.processedCount, 5);
  });

  it("applies transforms deterministically", () => {
    const first = mapRecord(
      {
        source: {
          id: "abc",
          name: "  Mixed Case  ",
          latitude: "41.1",
          longitude: "12.2"
        }
      },
      [
        {
          from: "source.name",
          to: "normalized.name",
          transform: "trim"
        },
        {
          from: "source.latitude",
          to: "normalized.latitude",
          transform: "to_number"
        }
      ]
    );
    const second = mapRecord(
      {
        source: {
          id: "abc",
          name: "  Mixed Case  ",
          latitude: "41.1",
          longitude: "12.2"
        }
      },
      [
        {
          from: "source.name",
          to: "normalized.name",
          transform: "trim"
        },
        {
          from: "source.latitude",
          to: "normalized.latitude",
          transform: "to_number"
        }
      ]
    );

    assert.deepEqual(first, second);
    assert.deepEqual(first.payload, {
      normalized: {
        name: "Mixed Case",
        latitude: 41.1
      }
    });
  });
});
