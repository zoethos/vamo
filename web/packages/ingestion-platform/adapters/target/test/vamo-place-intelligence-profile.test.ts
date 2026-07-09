import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";
import type { QueryResult } from "pg";

import type { StagedCandidate } from "../../../core/src/index.js";
import { runFixturePipeline } from "../../../core/src/index.js";
import {
  parsePipelineSpec,
  parseTargetProjectSpec,
  type PipelineSpec,
  type TargetProjectSpec
} from "../../../spec/src/index.js";
import { evaluateRecordPolicy } from "../../../policy/src/index.js";
import { planPostgresDryRun, type PgClientLike } from "../src/postgres-dry-run.js";

const bundleDir = "fixtures/imported/vamo-place-intelligence";

describe("vamo place-intelligence consumer profile", () => {
  it("stages Vamo canonical and source-ref payloads with derived keys and constants", async () => {
    const { pipeline } = readImportedSpecs();
    const result = await runFixturePipeline({
      pipeline,
      batchSize: 50,
      fixtureRoot: bundleDir
    });

    assert.equal(result.candidates.length, 36);

    const colosseum = result.candidates[0]?.payload;
    assert.ok(colosseum);
    const canonical = tablePayload(colosseum, "location_canonicals");
    const sourceRef = tablePayload(colosseum, "location_source_refs");

    assert.equal(canonical.canonical_key, "fsq-colosseum");
    assert.match(
      canonical.id as string,
      /^[a-f0-9]{8}-[a-f0-9]{4}-5[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/
    );
    assert.equal(canonical.source_provider, "fsq_os_places");
    assert.equal(canonical.promotion_state, "seeded");
    assert.equal(canonical.feature_type, "poi");
    assert.equal(sourceRef.provider, "fsq_os_places");
    assert.equal(sourceRef.source_place_id, "fsq_colosseum");
    assert.equal(sourceRef.canonical_id, canonical.id);

    const landmark = result.candidates.find(
      (candidate) => candidate.sourceScope?.category === "landmark"
    )?.payload;
    assert.ok(landmark);
    assert.equal(tablePayload(landmark, "location_canonicals").feature_type, "landmark");

    const restaurant = result.candidates.find(
      (candidate) => candidate.sourceScope?.category === "restaurant"
    )?.payload;
    assert.ok(restaurant);
    assert.equal(tablePayload(restaurant, "location_canonicals").feature_type, "poi");

    const transport = result.candidates.find(
      (candidate) => candidate.sourceScope?.category === "transport"
    )?.payload;
    assert.ok(transport);
    assert.equal(tablePayload(transport, "location_canonicals").feature_type, "poi");
  });

  it("produces a dry-run shipment plan against the Vamo cache schema fixture", async () => {
    const { pipeline, target } = readImportedSpecs();
    const run = await runFixturePipeline({
      pipeline,
      batchSize: 5,
      fixtureRoot: bundleDir
    });
    const client = new VamoPlaceSchemaClient({
      existingCanonicals: [run.candidates[0]]
    });

    const plan = await planPostgresDryRun({
      client,
      target,
      candidates: run.candidates
    });

    assert.equal(plan.compatible, true);
    assert.equal(plan.incompatibilities.length, 0);
    assert.deepEqual(
      plan.items
        .filter((item) => item.targetTable === "location_canonicals")
        .map((item) => item.operation),
      ["no_op", "insert", "insert"]
    );
    assert.deepEqual(
      plan.items
        .filter((item) => item.targetTable === "location_source_refs")
        .map((item) => item.operation),
      ["insert", "insert", "insert"]
    );
  });

  it("catches missing computed and constant upsert keys before shipment", async () => {
    const { pipeline, target } = readImportedSpecs();
    const run = await runFixturePipeline({
      pipeline,
      batchSize: 1,
      fixtureRoot: bundleDir
    });
    const badCandidate = structuredClone(run.candidates[0]) as StagedCandidate;
    delete tablePayload(badCandidate.payload, "location_canonicals").canonical_key;
    delete tablePayload(badCandidate.payload, "location_source_refs").provider;

    const plan = await planPostgresDryRun({
      client: new VamoPlaceSchemaClient(),
      target,
      candidates: [badCandidate]
    });

    assert.equal(plan.compatible, false);
    assert.equal(
      plan.incompatibilities.some(
        (issue) =>
          issue.code === "missing_upsert_key" &&
          issue.table === "location_canonicals" &&
          issue.column === "canonical_key"
      ),
      true
    );
    assert.equal(
      plan.incompatibilities.some(
        (issue) =>
          issue.code === "missing_upsert_key" &&
          issue.table === "location_source_refs" &&
          issue.column === "provider"
      ),
      true
    );
  });

  it("keeps global cache payloads free of user-scoped identifiers", async () => {
    const { pipeline } = readImportedSpecs();
    const run = await runFixturePipeline({
      pipeline,
      batchSize: 10,
      fixtureRoot: bundleDir
    });

    for (const candidate of run.candidates) {
      const serialized = JSON.stringify(candidate.payload);
      assert.equal(serialized.includes("user_id"), false);
      assert.equal(serialized.includes("trip_id"), false);
      assert.equal(serialized.includes("owner_id"), false);
    }
  });

  it("blocks reusable staging from live-only Google-like sources", () => {
    const { pipeline } = readImportedSpecs();
    const evaluations = evaluateRecordPolicy({
      pipeline: {
        ...pipeline,
        source: {
          ...pipeline.source,
          id: "google_places_api",
          license: {
            ...pipeline.source.license,
            name: "Google Places API",
            liveOnly: true,
            canStoreContent: false,
            canStoreMediaBytes: false
          }
        }
      },
      record: {
        source: {
          id: "google_live_only",
          name: "Live Only",
          latitude: 1,
          longitude: 2
        },
        attribution: "Google Places live response"
      },
      recordKey: "google_live_only"
    });

    assert.equal(
      evaluations.some(
        (evaluation) =>
          evaluation.decision === "deny" &&
          evaluation.reasonCode === "live_only_source"
      ),
      true
    );
  });
});

function readImportedSpecs(): { pipeline: PipelineSpec; target: TargetProjectSpec } {
  const pipeline = parsePipelineSpec(readFixture("pipeline.yaml"));
  const target = parseTargetProjectSpec(readFixture("target.yaml"));

  if (!pipeline.ok) {
    throw new Error(`Imported pipeline did not parse: ${JSON.stringify(pipeline.errors)}`);
  }
  if (!target.ok) {
    throw new Error(`Imported target did not parse: ${JSON.stringify(target.errors)}`);
  }

  return {
    pipeline: pipeline.value,
    target: target.value
  };
}

function readFixture(path: string): string {
  return readFileSync(`${bundleDir}/${path}`, "utf8");
}

class VamoPlaceSchemaClient implements PgClientLike {
  private readonly existingCanonicals: StagedCandidate[];

  constructor(input: { existingCanonicals?: StagedCandidate[] } = {}) {
    this.existingCanonicals = input.existingCanonicals ?? [];
  }

  async query<T extends Record<string, unknown> = Record<string, unknown>>(
    sql: string,
    values?: unknown[]
  ): Promise<QueryResult<T>> {
    if (sql.includes("information_schema.tables")) {
      const table = String(values?.[1]);
      return this.result([{ exists: table in vamoPlaceColumns } as unknown as T]);
    }

    if (sql.includes("information_schema.columns")) {
      const table = String(values?.[1]);
      return this.result(
        (vamoPlaceColumns[table] ?? []).map(
          (column) => ({ column_name: column }) as unknown as T
        )
      );
    }

    if (sql.includes('"public"."location_canonicals"')) {
      return this.result(
        this.existingCanonicals.map((candidate) => {
          const canonical = tablePayload(candidate.payload, "location_canonicals");
          return {
            ...canonical,
            latitude: String(canonical.latitude),
            longitude: String(canonical.longitude)
          } as unknown as T;
        })
      );
    }

    if (sql.includes('"public"."location_source_refs"')) {
      return this.result([]);
    }

    return this.result([]);
  }

  private result<T extends Record<string, unknown>>(rows: T[]): QueryResult<T> {
    return {
      rows,
      rowCount: rows.length,
      command: "SELECT",
      oid: 0,
      fields: []
    } as QueryResult<T>;
  }
}

function tablePayload(
  payload: Record<string, unknown>,
  table: string
): Record<string, unknown> {
  const value = payload[table];
  assert.equal(typeof value, "object");
  assert.notEqual(value, null);
  assert.equal(Array.isArray(value), false);
  return value as Record<string, unknown>;
}

// Keep in sync with Z:\vamo\supabase\migrations\20260625155733_place_intelligence_cache.sql.
const vamoPlaceColumns: Record<string, string[]> = {
  location_canonicals: [
    "id",
    "canonical_key",
    "display_name",
    "name_norm",
    "feature_type",
    "country_code",
    "admin1",
    "latitude",
    "longitude",
    "source_provider",
    "source_place_id",
    "source_rank",
    "attribution",
    "confidence",
    "promotion_state",
    "created_at",
    "updated_at"
  ],
  location_source_refs: [
    "id",
    "canonical_id",
    "provider",
    "source_place_id",
    "source_payload_hash",
    "attribution",
    "fetched_at",
    "expires_at",
    "created_at"
  ]
};
