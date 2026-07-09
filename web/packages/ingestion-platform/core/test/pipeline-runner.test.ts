import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";

import { mapRecord, runFixturePipeline, runSourcePipeline } from "../src/pipeline-runner.js";
import { parsePipelineSpec } from "../../spec/src/index.js";

const fixtureRoot = "fixtures/imported/vamo-place-intelligence";
const parsedPipeline = parsePipelineSpec(
  readFileSync(`${fixtureRoot}/pipeline.yaml`, "utf8")
);

if (!parsedPipeline.ok) {
  throw new Error(`Fixture pipeline did not parse: ${JSON.stringify(parsedPipeline.errors)}`);
}

const pipeline = parsedPipeline.value;
const parsedSnapshotPipeline = parsePipelineSpec(`
kind: ingestion.pipeline
version: 1
id: fsq-os-places-open-snapshot
name: FSQ OS Places Open Snapshot
owner: platform
source:
  id: fsq_os_places
  name: FSQ OS Places
  adapter: snapshot
  license:
    name: FSQ Open Source Places
    url: https://github.com/foursquare/os-places
    attribution: FSQ Open Source Places, Apache-2.0
    canStoreFacts: true
    canStoreContent: true
    canStoreMediaBytes: false
    liveOnly: false
  connection:
    snapshotPath: fixtures/open/fsq-os-places/sample.jsonl
    format: jsonl
target:
  id: vamo-place-intelligence
  adapter: supabase_postgres
  project: vamo
  profile: place-intelligence
  dryRunOnly: true
cursor:
  strategy: monotonic_row_id
  field: source_row_id
policyRequests:
  storeFacts: true
  storeContent: true
  storeMediaBytes: false
mappings:
  - from: source.id
    to: location_source_refs.source_place_id
  - value: fsq_os_places
    to: location_source_refs.provider
  - from: attribution
    to: location_source_refs.attribution
  - from: source.name
    to: location_canonicals.display_name
    transform: trim
qualityGates:
  - id: require-source-attribution
    type: attribution_present
    severity: block
  - id: reject-live-only-sources
    type: live_only_source_guard
    severity: block
`);

if (!parsedSnapshotPipeline.ok) {
  throw new Error(`Snapshot pipeline did not parse: ${JSON.stringify(parsedSnapshotPipeline.errors)}`);
}

const snapshotPipeline = parsedSnapshotPipeline.value;

describe("fixture pipeline runner", () => {
  it("stages candidates, policy evaluations, events, and checkpoint output", async () => {
    const result = await runFixturePipeline({
      pipeline,
      batchSize: 2,
      fixtureRoot
    });

    assert.equal(result.candidates.length, 2);
    assert.equal(result.deadLetters.length, 0);
    assert.equal(result.policyEvaluations.length, 8);
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
      batchSize: 3,
      checkpoint: first.checkpoint,
      fixtureRoot
    });

    assert.deepEqual(
      resumed.candidates.map((candidate) => candidate.recordKey),
      ["fsq_sagrada_familia"]
    );
    assert.equal(resumed.deadLetters.length, 2);
    assert.equal(resumed.deadLetters[0]?.reasonCode, "missing_mapped_field");
    assert.equal(
      resumed.events.some((event) => event.eventType === "policy_blocked"),
      true
    );
    assert.equal(resumed.checkpoint.cursorValue.last, 5);
    assert.equal(resumed.checkpoint.processedCount, 5);
  });

  it("runs a bounded open-dataset snapshot through policy and mapping", async () => {
    const result = await runSourcePipeline({
      pipeline: snapshotPipeline,
      batchSize: 10
    });

    assert.equal(snapshotPipeline.target.dryRunOnly, true);
    assert.deepEqual(
      result.candidates.map((candidate) => candidate.recordKey),
      ["fsq_colosseum", "fsq_eiffel_tower", "fsq_sagrada_familia"]
    );
    assert.equal(result.deadLetters.length, 1);
    assert.equal(
      result.events.some(
        (event) =>
          event.eventType === "policy_blocked" &&
          event.signal === "media_bytes_not_cacheable"
      ),
      true
    );
    const sourceRef = result.candidates[0]?.payload.location_source_refs as
      | Record<string, unknown>
      | undefined;
    assert.equal(
      sourceRef?.attribution,
      "FSQ Open Source Places, Apache-2.0"
    );
    assert.equal(result.checkpoint.cursorValue.last, 5);
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

  it("maps literal values, stable keys, and deterministic UUIDs", () => {
    const mapped = mapRecord(
      {
        source: {
          id: "FSQ Eiffel Tower"
        }
      },
      [
        {
          from: "source.id",
          to: "location_canonicals.id",
          transform: "deterministic_uuid"
        },
        {
          from: "source.id",
          to: "location_canonicals.canonical_key",
          transform: "stable_key"
        },
        {
          value: "fsq_os_places",
          to: "location_canonicals.source_provider"
        }
      ]
    );

    assert.equal(mapped.errors.length, 0);
    const canonical = mapped.payload.location_canonicals as Record<string, unknown>;
    assert.match(
      canonical.id as string,
      /^[a-f0-9]{8}-[a-f0-9]{4}-5[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/
    );
    assert.equal(canonical.canonical_key, "fsq-eiffel-tower");
    assert.equal(canonical.source_provider, "fsq_os_places");
  });

  it("maps Vamo source categories to supported target feature types", () => {
    for (const [sourceCategory, expectedFeatureType] of [
      ["poi", "poi"],
      ["restaurant", "poi"],
      ["transport", "poi"],
      ["hotel", "poi"],
      ["landmark", "landmark"]
    ] as const) {
      const mapped = mapRecord(
        {
          scope: {
            category: sourceCategory
          }
        },
        [
          {
            from: "scope.category",
            to: "location_canonicals.feature_type",
            transform: "vamo_feature_type"
          }
        ]
      );

      assert.equal(mapped.errors.length, 0);
      const canonical = mapped.payload.location_canonicals as Record<string, unknown>;
      assert.equal(canonical.feature_type, expectedFeatureType);
    }
  });
});
