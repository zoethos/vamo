import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  buildProductionPackageContentUnits,
  canonicalizeJson,
  hashProductionPackageCandidateContent
} from "../src/production-package-content-hash.js";
import type { StagedCandidate } from "../src/pipeline-runner.js";

function sampleCandidate(overrides: Partial<StagedCandidate> = {}): StagedCandidate {
  return {
    recordKey: "fsq_colosseum",
    sourceLineNumber: 1,
    sourceCursor: 1,
    targetProject: "vamo",
    targetProfile: "place-intelligence",
    sourceScope: { geography: "paris-france", category: "landmark" },
    payload: {
      location_canonicals: {
        canonical_key: "fsq-colosseum",
        display_name: "Colosseum",
        feature_type: "poi"
      },
      location_source_refs: {
        provider: "fsq_os_places",
        source_place_id: "fsq_colosseum",
        canonical_key: "fsq-colosseum"
      }
    },
    ...overrides
  };
}

describe("production package content hash", () => {
  it("is stable across object key ordering", () => {
    const left = sampleCandidate({
      payload: {
        location_canonicals: {
          display_name: "Colosseum",
          canonical_key: "fsq-colosseum",
          feature_type: "poi"
        },
        location_source_refs: {
          source_place_id: "fsq_colosseum",
          provider: "fsq_os_places",
          canonical_key: "fsq-colosseum"
        }
      }
    });
    const right = sampleCandidate({
      payload: {
        location_source_refs: {
          canonical_key: "fsq-colosseum",
          provider: "fsq_os_places",
          source_place_id: "fsq_colosseum"
        },
        location_canonicals: {
          feature_type: "poi",
          canonical_key: "fsq-colosseum",
          display_name: "Colosseum"
        }
      }
    });

    assert.equal(
      hashProductionPackageCandidateContent([left]),
      hashProductionPackageCandidateContent([right])
    );
  });

  it("changes when deliverable content changes", () => {
    const baseline = hashProductionPackageCandidateContent([sampleCandidate()]);
    const changed = hashProductionPackageCandidateContent([
      sampleCandidate({
        payload: {
          location_canonicals: {
            canonical_key: "fsq-colosseum",
            display_name: "Different Name",
            feature_type: "poi"
          },
          location_source_refs: {
            provider: "fsq_os_places",
            source_place_id: "fsq_colosseum",
            canonical_key: "fsq-colosseum"
          }
        }
      })
    ]);
    assert.notEqual(baseline, changed);
  });

  it("sorts candidates and items deterministically", () => {
    const units = buildProductionPackageContentUnits([
      sampleCandidate({ recordKey: "z-last" }),
      sampleCandidate({ recordKey: "a-first" })
    ]);
    assert.deepEqual(
      units.map((unit) => unit.recordKey),
      ["a-first", "z-last"]
    );
    assert.ok(units.every((unit) => unit.items.length > 0));
  });

  it("canonicalizes nested JSON with sorted keys", () => {
    const serialized = canonicalizeJson({ b: 1, a: { d: 2, c: 3 } });
    assert.equal(serialized, '{"a":{"c":3,"d":2},"b":1}');
  });
});
