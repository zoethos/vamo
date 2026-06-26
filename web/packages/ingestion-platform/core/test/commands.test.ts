import assert from "node:assert/strict";
import { describe, it } from "node:test";

import type { IngestionTaskStatus } from "../src/control-models.js";
import { planIngestionCommand, type CommandStateSnapshot } from "../src/commands.js";
import type { CommandTaskRow } from "../src/run-state.js";
import type { WorkerLeaseRow } from "../src/leases.js";

const now = "2026-06-26T12:00:00.000Z";
const actor = { type: "operator" as const, id: "founder" };

describe("ingestion command planner", () => {
  it("starts eligible queued and paused tasks and emits an audit event", () => {
    const plan = planIngestionCommand(snapshot(), {
      command: "start",
      scope: { type: "cluster" },
      actor,
      now
    });

    assert.equal(plan.ok, true);
    assert.deepEqual(
      plan.taskPatches.map((patch) => [patch.taskId, patch.status]),
      [
        ["task-queued-a", "running"],
        ["task-paused-b", "running"]
      ]
    );
    assert.equal(plan.auditEvent.action, "ingestion.start");
    assert.equal(plan.auditEvent.payload.accepted, true);
    assert.deepEqual(plan.auditEvent.payload.changedTaskIds, ["task-queued-a", "task-paused-b"]);
  });

  it("pauses only tasks in the selected target and preserves checkpoint scope", () => {
    const plan = planIngestionCommand(snapshot(), {
      command: "pause",
      scope: { type: "target", targetId: "target-a" },
      actor,
      now
    });

    assert.equal(plan.ok, true);
    assert.deepEqual(
      plan.taskPatches.map((patch) => patch.taskId),
      ["task-queued-a", "task-running-a"]
    );
    assert.equal(
      plan.taskPatches.some((patch) => patch.taskId === "task-running-b"),
      false
    );
    assert.equal(
      plan.taskPatches.every((patch) => patch.preserveCheckpoint && patch.checkpointScope),
      true
    );
  });

  it("shutdown pauses selected running work and releases active leases", () => {
    const plan = planIngestionCommand(snapshot(), {
      command: "shutdown",
      scope: { type: "worker", workerId: "worker-1" },
      actor,
      now
    });

    assert.equal(plan.ok, true);
    assert.deepEqual(plan.taskPatches.map((patch) => patch.taskId), ["task-running-a"]);
    assert.deepEqual(
      plan.leasePatches.map((patch) => [patch.leaseId, patch.status, patch.releaseReason]),
      [["lease-running-a", "released", "operator_shutdown"]]
    );
  });

  it("blocks reset without an audit reason before touching tasks or leases", () => {
    const plan = planIngestionCommand(snapshot(), {
      command: "reset",
      scope: { type: "target", targetId: "target-c" },
      actor,
      now
    });

    assert.equal(plan.ok, false);
    assert.equal(plan.errors[0]?.code, "reset_reason_required");
    assert.equal(plan.taskPatches.length, 0);
    assert.equal(plan.leasePatches.length, 0);
    assert.equal(plan.auditEvent.payload.accepted, false);
  });

  it("resets only failed or blocked tasks and releases their active leases", () => {
    const plan = planIngestionCommand(snapshot(), {
      command: "reset",
      scope: { type: "target", targetId: "target-c" },
      actor,
      now,
      reason: "provider policy reviewed"
    });

    assert.equal(plan.ok, true);
    assert.deepEqual(
      plan.taskPatches.map((patch) => [patch.taskId, patch.previousStatus, patch.status]),
      [
        ["task-failed-c", "failed", "queued"],
        ["task-blocked-c", "blocked", "queued"]
      ]
    );
    assert.equal(plan.taskPatches.every((patch) => patch.errorCode === null), true);
    assert.deepEqual(
      plan.leasePatches.map((patch) => patch.leaseId),
      ["lease-failed-c", "lease-blocked-c"]
    );
    assert.equal(plan.auditEvent.reason, "provider policy reviewed");
  });

  it("emits a rejected audit event when the scope matches no tasks", () => {
    const plan = planIngestionCommand(snapshot(), {
      command: "pause",
      scope: { type: "target", targetId: "missing-target" },
      actor,
      now
    });

    assert.equal(plan.ok, false);
    assert.equal(plan.errors[0]?.code, "no_matching_tasks");
    assert.equal(plan.auditEvent.payload.accepted, false);
    assert.equal(plan.auditEvent.targetId, "missing-target");
  });
});

function snapshot(): CommandStateSnapshot {
  return {
    projectId: "vamo",
    tasks: [
      task("task-queued-a", "target-a", "queued"),
      task("task-running-a", "target-a", "running", "worker-1"),
      task("task-paused-b", "target-b", "paused"),
      task("task-running-b", "target-b", "running", "worker-2"),
      task("task-failed-c", "target-c", "failed", "worker-3"),
      task("task-blocked-c", "target-c", "blocked", "worker-4")
    ],
    leases: [
      lease("lease-running-a", "task-running-a", "worker-1"),
      lease("lease-running-b", "task-running-b", "worker-2"),
      lease("lease-failed-c", "task-failed-c", "worker-3"),
      lease("lease-blocked-c", "task-blocked-c", "worker-4")
    ]
  };
}

function task(
  id: string,
  targetId: string,
  status: IngestionTaskStatus,
  workerId?: string
): CommandTaskRow {
  return {
    id,
    targetId,
    status,
    workerId,
    checkpointScope: `${targetId}.cursor`,
    errorCode: status === "failed" || status === "blocked" ? "fixture_error" : null,
    errorMessage: status === "failed" || status === "blocked" ? "needs review" : null
  };
}

function lease(id: string, taskId: string, workerId: string): WorkerLeaseRow {
  return {
    id,
    taskId,
    workerId,
    leaseToken: `${id}-token`,
    status: "active",
    heartbeatAt: "2026-06-26T11:59:30.000Z",
    expiresAt: "2026-06-26T12:01:00.000Z"
  };
}
