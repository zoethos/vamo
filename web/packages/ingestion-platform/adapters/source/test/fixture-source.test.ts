import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { readFixtureBatch } from "../src/fixture-source.js";

const fixturePath = "fixtures/platform/source-sample.jsonl";

describe("fixture source adapter", () => {
  it("reads bounded fixture batches without network access", () => {
    const batch = readFixtureBatch({
      fixturePath,
      cursorField: "source_row_id",
      limit: 2
    });

    assert.equal(batch.records.length, 2);
    assert.equal(batch.issues.length, 0);
    assert.equal(batch.records[0]?.recordKey, "fsq_colosseum");
    assert.equal(batch.lastCursorValue, 2);
  });

  it("resumes from the row after the checkpoint cursor", () => {
    const batch = readFixtureBatch({
      fixturePath,
      cursorField: "source_row_id",
      startAfter: 2,
      limit: 10
    });

    assert.deepEqual(
      batch.records.map((record) => record.cursorValue),
      [3, 4, 5]
    );
    assert.equal(batch.lastCursorValue, 5);
  });

  it("classifies invalid JSON lines as source issues", () => {
    const batch = readFixtureBatch({
      fixturePath: "fixtures/platform/source-invalid-json.jsonl",
      cursorField: "source_row_id",
      limit: 5
    });

    assert.equal(batch.records.length, 1);
    assert.equal(batch.issues.length, 1);
    assert.equal(batch.issues[0]?.reasonCode, "invalid_json");
  });
});
