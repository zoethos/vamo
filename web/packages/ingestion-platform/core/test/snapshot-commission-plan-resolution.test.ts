import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { evaluateSnapshotCommissionPlanResolution } from "../src/snapshot-commission-plan-resolution.js";

describe("evaluateSnapshotCommissionPlanResolution", () => {
  it("prefers the autonomy policy batch plan when queue context agrees", () => {
    const resolution = evaluateSnapshotCommissionPlanResolution({
      policyBatchPlanKey: "vamo-eu-poi-sample",
      queuePlanKey: "vamo-eu-poi-sample"
    });
    assert.deepEqual(resolution, {
      ok: true,
      planKey: "vamo-eu-poi-sample",
      source: "autonomy_policy"
    });
  });

  it("falls back to queue context when the policy does not pin a plan", () => {
    const resolution = evaluateSnapshotCommissionPlanResolution({
      queuePlanKey: "vamo-eu-poi-sample"
    });
    assert.deepEqual(resolution, {
      ok: true,
      planKey: "vamo-eu-poi-sample",
      source: "queue_context"
    });
  });

  it("fails closed when policy and queue disagree", () => {
    const resolution = evaluateSnapshotCommissionPlanResolution({
      policyBatchPlanKey: "policy-plan",
      queuePlanKey: "queue-plan"
    });
    assert.deepEqual(resolution, {
      ok: false,
      code: "commission_plan_context_mismatch"
    });
  });

  it("returns plan_not_found when neither policy nor queue provide a plan", () => {
    const resolution = evaluateSnapshotCommissionPlanResolution({});
    assert.deepEqual(resolution, { ok: false, code: "plan_not_found" });
  });
});
