import assert from "node:assert/strict";
import { describe, it } from "node:test";

import type { StagedCandidate } from "../src/pipeline-runner.js";
import { sampleProgressiveRunSnapshot } from "../src/progressive-read-model.js";
import { buildProductionInboxPackage } from "../src/shipment-package.js";

const report = sampleProgressiveRunSnapshot.entries[0]?.report;
if (!report) {
  throw new Error("sample progressive report missing");
}

describe("production inbox package assembly", () => {
  it("builds generic JSONB items without client-side checksums", () => {
    const pkg = buildProductionInboxPackage({
      packageId: "production-inbox:vamo-place-intelligence-staging:approval:9",
      consumerKey: "vamo",
      runReport: report,
      candidates: [candidate()],
      approvedBy: "supabase:user-1",
      approvalReason: "first production inbox delivery"
    });

    assert.equal(pkg.targetEnvironment, "production");
    assert.equal(pkg.schemaContract, "vamo-place-intelligence@1");
    assert.equal(pkg.items.length, 2);
    assert.deepEqual(
      pkg.items.map((item) => item.targetTable),
      ["location_canonicals", "location_source_refs"]
    );
    assert.ok(!("payloadChecksum" in pkg.items[0]!));
    assert.ok(!("checksum" in pkg));
  });

  it("requires an audit actor, reason, and at least one deliverable item", () => {
    assert.throws(
      () =>
        buildProductionInboxPackage({
          packageId: "pkg",
          consumerKey: "vamo",
          runReport: report,
          candidates: [],
          approvedBy: "supabase:user-1",
          approvalReason: "x"
        }),
      /no deliverable items/
    );
    assert.throws(
      () =>
        buildProductionInboxPackage({
          packageId: "pkg",
          consumerKey: "vamo",
          runReport: report,
          candidates: [candidate()],
          approvedBy: "",
          approvalReason: "x"
        }),
      /approvedBy/
    );
  });
});

function candidate(): StagedCandidate {
  return {
    recordKey: "fsq_colosseum",
    sourceLineNumber: 1,
    sourceCursor: 1,
    targetProject: "vamo",
    targetProfile: "place-intelligence",
    sourceScope: { geography: "rome-italy", category: "poi" },
    payload: {
      location_canonicals: {
        canonical_key: "fsq-colosseum",
        display_name: "Colosseum",
        name_norm: "colosseum",
        feature_type: "poi",
        latitude: 41.8902,
        longitude: 12.4922,
        source_provider: "fsq_os_places",
        source_place_id: "fsq_colosseum",
        attribution: "FSQ Open Source Places",
        promotion_state: "seeded"
      },
      location_source_refs: {
        canonical_key: "fsq-colosseum",
        provider: "fsq_os_places",
        source_place_id: "fsq_colosseum",
        attribution: "FSQ Open Source Places"
      }
    }
  };
}
