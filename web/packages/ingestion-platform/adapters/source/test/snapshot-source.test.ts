import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { readSnapshotBatch } from "../src/snapshot-source.js";

const snapshotPath = "fixtures/open/fsq-os-places/sample.jsonl";
const metadata = {
  datasetId: "fsq_os_places",
  datasetName: "FSQ OS Places",
  licenseName: "FSQ Open Source Places",
  attribution: "FSQ Open Source Places, Apache-2.0",
  datasetUrl: "https://github.com/foursquare/os-places"
};

describe("snapshot source adapter", () => {
  it("reads bounded open-dataset snapshots and attaches attribution metadata", () => {
    const batch = readSnapshotBatch({
      snapshotPath,
      cursorField: "source_row_id",
      limit: 2,
      metadata
    });

    assert.equal(batch.records.length, 2);
    assert.equal(batch.issues.length, 0);
    assert.equal(batch.records[0]?.recordKey, "fsq_colosseum");
    assert.equal(batch.lastCursorValue, 2);
    assert.equal(batch.records[0]?.record.attribution, metadata.attribution);
    assert.deepEqual(batch.records[0]?.record._ingestion, {
      sourceAdapter: "snapshot",
      datasetId: "fsq_os_places",
      datasetName: "FSQ OS Places",
      licenseName: "FSQ Open Source Places",
      attribution: metadata.attribution,
      datasetUrl: "https://github.com/foursquare/os-places",
      downloadedAt: undefined,
      snapshotFile: "sample.jsonl"
    });
  });

  it("resumes from the cursor after the checkpoint", () => {
    const batch = readSnapshotBatch({
      snapshotPath,
      cursorField: "source_row_id",
      startAfter: 2,
      limit: 10,
      metadata
    });

    assert.deepEqual(
      batch.records.map((record) => record.cursorValue),
      [3, 4, 5]
    );
    assert.equal(batch.lastCursorValue, 5);
  });

  it("rejects URL and proxy/VPN-style connection controls", () => {
    assert.throws(
      () =>
        readSnapshotBatch({
          snapshotPath: "https://example.com/open-dataset.jsonl",
          limit: 1,
          metadata
        }),
      /local files/
    );
    assert.throws(
      () =>
        readSnapshotBatch({
          snapshotPath,
          connection: {
            proxy_url: "http://127.0.0.1:8888"
          },
          limit: 1,
          metadata
        }),
      /network\/evasion/
    );
  });

  it("classifies rows without row or source attribution", () => {
    const batch = readSnapshotBatch({
      snapshotPath,
      cursorField: "source_row_id",
      limit: 1,
      metadata: {
        ...metadata,
        attribution: ""
      }
    });

    assert.equal(batch.records.length, 0);
    assert.equal(batch.issues.length, 5);
    assert.equal(batch.issues[0]?.reasonCode, "missing_attribution");
  });
});
