import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";

import {
  SNAPSHOT_COMMISSION_CONFIRMATION_STATE,
  canTransitionSnapshotCommissionStatus,
  parseSnapshotCommissionRequestCreate
} from "../src/snapshot-commission-request.js";

const requestModule = readFileSync("core/src/snapshot-commission-request.ts", "utf8");

describe("parseSnapshotCommissionRequestCreate", () => {
  it("accepts a valid commissioning request without trusting planKey or sourceKey hints", () => {
    const parsed = parseSnapshotCommissionRequestCreate({
      projectKey: "vamo",
      planKey: "forged-plan-key",
      sourceKey: "forged-source-key",
      countries: ["italy", "france"],
      categories: ["poi", "landmark"],
      maxRowsPerScope: 250,
      auditReason: "Commission bounded FSQ snapshot for next release cycle.",
      confirmedState: SNAPSHOT_COMMISSION_CONFIRMATION_STATE
    });

    assert.equal(parsed.ok, true);
    if (!parsed.ok) return;
    assert.equal("planKey" in parsed.request, false);
    assert.equal("sourceKey" in parsed.request, false);
    assert.deepEqual(parsed.request.countries, ["italy", "france"]);
    assert.equal(parsed.request.maxRowsPerScope, 250);
  });

  it("rejects missing audit reason", () => {
    const parsed = parseSnapshotCommissionRequestCreate({
      projectKey: "vamo",
      countries: ["italy"],
      categories: ["poi"],
      auditReason: "   ",
      confirmedState: SNAPSHOT_COMMISSION_CONFIRMATION_STATE
    });

    assert.equal(parsed.ok, false);
    if (parsed.ok) return;
    assert.equal(parsed.code, "audit_reason_required");
  });

  it("rejects confirmation state mismatch", () => {
    const parsed = parseSnapshotCommissionRequestCreate({
      projectKey: "vamo",
      countries: ["italy"],
      categories: ["poi"],
      auditReason: "Commission snapshot.",
      confirmedState: "execute_now"
    });

    assert.equal(parsed.ok, false);
    if (parsed.ok) return;
    assert.equal(parsed.code, "confirmed_state_mismatch");
  });
});

describe("canTransitionSnapshotCommissionStatus", () => {
  it("allows the commissioning lifecycle", () => {
    assert.equal(canTransitionSnapshotCommissionStatus("requested", "running"), true);
    assert.equal(canTransitionSnapshotCommissionStatus("running", "release_registered"), true);
    assert.equal(canTransitionSnapshotCommissionStatus("release_registered", "activation_pending"), true);
    assert.equal(canTransitionSnapshotCommissionStatus("requested", "failed"), true);
    assert.equal(canTransitionSnapshotCommissionStatus("running", "failed"), true);
  });

  it("blocks terminal transitions and automatic activation shortcuts", () => {
    assert.equal(canTransitionSnapshotCommissionStatus("activation_pending", "running"), false);
    assert.equal(canTransitionSnapshotCommissionStatus("failed", "requested"), false);
    assert.equal(canTransitionSnapshotCommissionStatus("requested", "activation_pending"), false);
  });
});

describe("snapshot commission request module boundary", () => {
  it("does not import provider adapter modules", () => {
    assert.doesNotMatch(requestModule, /adapters\/source/);
    assert.doesNotMatch(requestModule, /fsq-os-places-portal-iceberg-acquire/);
    assert.doesNotMatch(requestModule, /@duckdb\/node-api/);
  });
});
