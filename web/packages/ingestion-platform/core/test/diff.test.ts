import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { buildShipmentDiff, stableChecksum } from "../src/diff.js";

describe("shipment diff", () => {
  it("creates deterministic insert/update/no-op shipment items", () => {
    const candidateRows = [
      {
        recordKey: "new",
        payload: {
          source_id: "new",
          display_name: "New Place"
        }
      },
      {
        recordKey: "same",
        payload: {
          source_id: "same",
          display_name: "Same Place"
        }
      },
      {
        recordKey: "changed",
        payload: {
          source_id: "changed",
          display_name: "Changed Place"
        }
      }
    ];
    const first = buildShipmentDiff({
      targetTable: "public.generic_places",
      upsertKeys: ["source_id"],
      candidateRows,
      existingRows: [
        {
          source_id: "same",
          display_name: "Same Place"
        },
        {
          source_id: "changed",
          display_name: "Old Place"
        }
      ]
    });
    const second = buildShipmentDiff({
      targetTable: "public.generic_places",
      upsertKeys: ["source_id"],
      candidateRows,
      existingRows: [
        {
          source_id: "same",
          display_name: "Same Place"
        },
        {
          source_id: "changed",
          display_name: "Old Place"
        }
      ]
    });

    assert.deepEqual(first, second);
    assert.deepEqual(
      first.map((item) => item.operation),
      ["insert", "no_op", "update"]
    );
    assert.equal(first[0]?.idempotencyKey, "public.generic_places:source_id=new");
  });

  it("checksums objects with stable key ordering", () => {
    assert.equal(
      stableChecksum({
        b: "two",
        a: "one"
      }),
      stableChecksum({
        a: "one",
        b: "two"
      })
    );
  });

  it("treats numeric and timestamp column equivalents as no-ops", () => {
    const result = buildShipmentDiff({
      targetTable: "public.location_canonicals",
      upsertKeys: ["canonical_key"],
      candidateRows: [
        {
          recordKey: "colosseum",
          payload: {
            canonical_key: "fsq-colosseum",
            latitude: 41.8902,
            longitude: 12.4922,
            updated_at: "2026-06-26T12:00:00.000Z"
          }
        }
      ],
      existingRows: [
        {
          canonical_key: "fsq-colosseum",
          latitude: "41.890200",
          longitude: "12.492200",
          updated_at: new Date("2026-06-26T12:00:00.000Z")
        }
      ]
    });

    assert.equal(result[0]?.operation, "no_op");
  });

  it("uses column type hints for numeric names outside the fallback list", () => {
    const result = buildShipmentDiff({
      targetTable: "public.geonames",
      upsertKeys: ["geonames_id"],
      candidateRows: [
        {
          recordKey: "rome",
          payload: {
            geonames_id: "3169070",
            population: 2873000,
            elevation: 21
          }
        }
      ],
      existingRows: [
        {
          geonames_id: "3169070",
          population: "2873000",
          elevation: "21"
        }
      ],
      columnTypes: {
        geonames_id: "text",
        population: "integer",
        elevation: "numeric"
      }
    });

    assert.equal(result[0]?.operation, "no_op");
  });
});
