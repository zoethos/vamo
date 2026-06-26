import assert from "node:assert/strict";
import { describe, it } from "node:test";

import type { IngestionTaskStatus } from "../src/control-models.js";
import {
  planTaskCommandTransition,
  type CommandTaskRow,
  type IngestionCommandKind
} from "../src/run-state.js";

const now = "2026-06-26T12:00:00.000Z";

describe("ingestion task run-state policy", () => {
  it("transitions only through the supported command matrix", () => {
    const cases: Array<[IngestionTaskStatus, IngestionCommandKind, IngestionTaskStatus]> = [
      ["queued", "start", "running"],
      ["paused", "start", "running"],
      ["running", "pause", "paused"],
      ["queued", "pause", "paused"],
      ["running", "shutdown", "paused"],
      ["failed", "reset", "queued"],
      ["blocked", "reset", "queued"]
    ];

    for (const [fromStatus, command, toStatus] of cases) {
      const outcome = planTaskCommandTransition({
        task: task(fromStatus),
        command,
        reason: command === "reset" ? "operator reviewed failure" : undefined,
        now
      });

      assert.equal(outcome.patch?.previousStatus, fromStatus, `${fromStatus} ${command}`);
      assert.equal(outcome.patch?.status, toStatus, `${fromStatus} ${command}`);
      assert.equal(outcome.patch?.preserveCheckpoint, true);
      assert.equal(outcome.patch?.checkpointScope, "target.cursor");
    }
  });

  it("fails invalid transitions with structured errors", () => {
    const failedStart = planTaskCommandTransition({
      task: task("failed"),
      command: "start",
      now
    });
    const runningReset = planTaskCommandTransition({
      task: task("running"),
      command: "reset",
      reason: "not failed",
      now
    });
    const resetWithoutReason = planTaskCommandTransition({
      task: task("blocked"),
      command: "reset",
      now
    });

    assert.equal(failedStart.error?.code, "reset_required");
    assert.equal(runningReset.error?.code, "invalid_transition");
    assert.equal(resetWithoutReason.error?.code, "reset_reason_required");
  });

  it("treats already-running and already-paused tasks as no-op skips", () => {
    const runningStart = planTaskCommandTransition({
      task: task("running"),
      command: "start",
      now
    });
    const pausedPause = planTaskCommandTransition({
      task: task("paused"),
      command: "pause",
      now
    });

    assert.equal(runningStart.skipped?.reason, "already_in_state");
    assert.equal(pausedPause.skipped?.reason, "already_in_state");
  });
});

function task(status: IngestionTaskStatus): CommandTaskRow {
  return {
    id: `task-${status}`,
    targetId: "target-a",
    status,
    checkpointScope: "target.cursor"
  };
}
