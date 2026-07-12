import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  AUTONOMY_POLICY_BATCH_PLAN_KEY,
  readAutonomyBatchPlanKeyFromSummary,
  resolveAutonomyDrainBatchPlanKey
} from "../src/batch-plan-selection.js";

describe("batch plan selection for autonomy drain", () => {
  it("reads batchPlanKey from policy summary aliases", () => {
    assert.equal(
      readAutonomyBatchPlanKeyFromSummary({
        [AUTONOMY_POLICY_BATCH_PLAN_KEY]: "vamo-eu-full-data-v1"
      }),
      "vamo-eu-full-data-v1"
    );
    assert.equal(
      readAutonomyBatchPlanKeyFromSummary({ queuePlanKey: "vamo-eu-poi-sample" }),
      "vamo-eu-poi-sample"
    );
    assert.equal(
      readAutonomyBatchPlanKeyFromSummary({ batch_plan_key: "legacy-plan" }),
      "legacy-plan"
    );
    assert.equal(readAutonomyBatchPlanKeyFromSummary({}), undefined);
  });

  it("prefers explicit override over policy summary", () => {
    assert.equal(
      resolveAutonomyDrainBatchPlanKey({
        batchPlanKey: "override-plan",
        policy: {
          batchPlanKey: "policy-field-plan",
          summary: { batchPlanKey: "summary-plan" }
        }
      }),
      "override-plan"
    );
  });

  it("falls back to policy field then summary", () => {
    assert.equal(
      resolveAutonomyDrainBatchPlanKey({
        policy: {
          batchPlanKey: "policy-field-plan",
          summary: { batchPlanKey: "summary-plan" }
        }
      }),
      "policy-field-plan"
    );
    assert.equal(
      resolveAutonomyDrainBatchPlanKey({
        policy: { summary: { batchPlanKey: "summary-plan" } }
      }),
      "summary-plan"
    );
    assert.equal(
      resolveAutonomyDrainBatchPlanKey({
        policy: {}
      }),
      undefined
    );
  });
});
