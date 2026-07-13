import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  isCrossPlanPackageLifecycleStatus,
  resolveCrossPlanPackageLifecycles
} from "../src/batch-cross-plan-package-lifecycle.js";

describe("cross-plan production package lifecycle", () => {
  it("resolves the latest occupied package state per unit", () => {
    const lifecycles = resolveCrossPlanPackageLifecycles([
      {
        unitKey: "vamo-place-intelligence:barcelona-spain:landmark",
        planKey: "vamo-eu-poi-sample",
        waveKey: "wave:60",
        status: "approved",
        updatedAt: "2026-07-07T10:00:00.000Z"
      },
      {
        unitKey: "vamo-place-intelligence:barcelona-spain:landmark",
        planKey: "vamo-eu-poi-sample",
        waveKey: "wave:62",
        status: "consumer_applied",
        updatedAt: "2026-07-07T11:00:00.000Z"
      },
      {
        unitKey: "vamo-place-intelligence:rome-italy:poi",
        planKey: "vamo-eu-poi-sample",
        waveKey: "wave:63",
        status: "consumer_apply_pending",
        updatedAt: "2026-07-07T11:00:00.000Z"
      }
    ]);

    assert.deepEqual(lifecycles, {
      "vamo-place-intelligence:barcelona-spain:landmark": {
        planKey: "vamo-eu-poi-sample",
        waveKey: "wave:62",
        status: "consumer_applied"
      },
      "vamo-place-intelligence:rome-italy:poi": {
        planKey: "vamo-eu-poi-sample",
        waveKey: "wave:63",
        status: "consumer_apply_pending"
      }
    });
  });

  it("recognizes only package states that keep a scope occupied", () => {
    assert.equal(isCrossPlanPackageLifecycleStatus("consumer_applied"), true);
    assert.equal(isCrossPlanPackageLifecycleStatus("released"), false);
    assert.equal(isCrossPlanPackageLifecycleStatus("expired"), false);
  });
});
