import assert from "node:assert/strict";
import { describe, it } from "node:test";

import type { IngestionTaskStatus } from "../src/control-models.js";
import {
  buildIngestionDashboardView,
  sampleControlPlaneSnapshot,
  viewStatusTone,
  type ControlPlaneSnapshot,
  type ControlTargetRow
} from "../src/read-model.js";

function snapshotWithTargetStatus(status: IngestionTaskStatus): ControlPlaneSnapshot {
  const target: ControlTargetRow = {
    name: "Probe",
    source: "Fixture",
    scope: "test",
    instanceId: "worker-x",
    status,
    checkpoint: "cp.0",
    throughput: "n/a",
    lastSignal: "probe"
  };
  return { ...sampleControlPlaneSnapshot, targets: [target] };
}

describe("ingestion dashboard read model", () => {
  it("transforms control-plane rows into every dashboard section", () => {
    const view = buildIngestionDashboardView(sampleControlPlaneSnapshot);

    assert.equal(view.instances.length, 4);
    assert.equal(view.targets.length, 7);
    assert.equal(view.events.length, 5);
    assert.equal(view.stats.length, 6);
    assert.equal(view.signals.length, 4);
    assert.equal(view.actions.length, 4);
    assert.ok(view.policyLocks.length > 0);
  });

  it("maps task status to view status, tone, and next action", () => {
    const cases: Array<[IngestionTaskStatus, string, string]> = [
      ["queued", "queued", "Start"],
      ["running", "running", "Pause"],
      ["paused", "paused", "Resume"],
      ["blocked", "blocked", "Review"],
      ["succeeded", "complete", "Review"],
      ["failed", "stopped", "Restart"],
      ["cancelled", "stopped", "Restart"]
    ];

    for (const [domainStatus, viewStatus, nextAction] of cases) {
      const view = buildIngestionDashboardView(snapshotWithTargetStatus(domainStatus));
      const target = view.targets[0];
      assert.equal(target?.status, viewStatus, `status ${domainStatus}`);
      assert.equal(target?.nextAction, nextAction, `action ${domainStatus}`);
    }

    assert.equal(viewStatusTone("blocked"), "danger");
    assert.equal(viewStatusTone("stopped"), "danger");
    assert.equal(viewStatusTone("running"), "good");
    assert.equal(viewStatusTone("paused"), "watch");
  });

  it("maps event severity to tone", () => {
    const view = buildIngestionDashboardView(sampleControlPlaneSnapshot);
    const blocked = view.events.find((event) => event.signal === "policy_guard_blocked_storage");
    const ok = view.events.find((event) => event.signal === "checkpoint_committed");

    assert.equal(blocked?.tone, "danger");
    assert.equal(ok?.tone, "good");
  });

  it("formats heartbeats, idle workers, and derived signal counts", () => {
    const view = buildIngestionDashboardView(sampleControlPlaneSnapshot);

    assert.equal(view.instances[0]?.heartbeat, "15s ago");
    assert.equal(view.instances[2]?.heartbeat, "2m ago");
    assert.equal(view.instances[3]?.heartbeat, "Ready");

    const workers = view.signals.find((signal) => signal.label === "Workers");
    // 2 running + 1 paused + 1 queued instance = 4 online.
    assert.equal(workers?.value, "4 online");
    assert.equal(workers?.detail, "2 active, 1 paused, 1 queued");

    const yieldSignal = view.signals.find((signal) => signal.label === "Cache yield");
    assert.equal(yieldSignal?.value, "72%");
  });

  it("formats stat counters without locale dependence", () => {
    const view = buildIngestionDashboardView(sampleControlPlaneSnapshot);
    const promoted = view.stats.find((stat) => stat.label === "Canonicals promoted");
    const avoided = view.stats.find((stat) => stat.label === "Calls avoided");

    assert.equal(promoted?.value, "128,440");
    assert.equal(avoided?.value, "31.8k");
  });

  it("is deterministic for the same snapshot", () => {
    assert.deepEqual(
      buildIngestionDashboardView(sampleControlPlaneSnapshot),
      buildIngestionDashboardView(sampleControlPlaneSnapshot)
    );
  });
});
