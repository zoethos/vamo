import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  AUTONOMY_CYCLE_EVENT_NAMES,
  isAutonomyCycleEventName
} from "../src/autonomy-telemetry.js";

describe("autonomy telemetry", () => {
  it("reserves cycle and action event names", () => {
    assert.deepEqual(AUTONOMY_CYCLE_EVENT_NAMES, [
      "autonomy.cycle.started",
      "autonomy.cycle.advanced",
      "autonomy.cycle.paused",
      "autonomy.cycle.completed",
      "autonomy.cycle.failed",
      "autonomy.action.applied"
    ]);
    assert.equal(isAutonomyCycleEventName("autonomy.cycle.paused"), true);
    assert.equal(isAutonomyCycleEventName("autonomy.unknown"), false);
  });
});
