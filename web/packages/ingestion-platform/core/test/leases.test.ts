import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  expireStaleLeases,
  releaseActiveLeasesForTasks,
  type WorkerLeaseRow
} from "../src/leases.js";

const now = "2026-06-26T12:00:00.000Z";

describe("ingestion worker lease policy", () => {
  it("expires active leases whose heartbeat window has elapsed", () => {
    const patches = expireStaleLeases(
      [
        lease("lease-expired", "task-a", "active", "2026-06-26T11:59:59.000Z"),
        lease("lease-live", "task-b", "active", "2026-06-26T12:00:30.000Z"),
        lease("lease-released", "task-c", "released", "2026-06-26T11:59:00.000Z")
      ],
      now
    );

    assert.equal(patches.length, 1);
    assert.equal(patches[0]?.leaseId, "lease-expired");
    assert.equal(patches[0]?.status, "expired");
    assert.equal(patches[0]?.releaseReason, "lease_timeout");
  });

  it("releases only active leases for selected tasks", () => {
    const patches = releaseActiveLeasesForTasks(
      [
        lease("lease-a", "task-a", "active", "2026-06-26T12:01:00.000Z"),
        lease("lease-b", "task-b", "active", "2026-06-26T12:01:00.000Z"),
        lease("lease-c", "task-c", "released", "2026-06-26T12:01:00.000Z")
      ],
      new Set(["task-a", "task-c"]),
      now,
      "operator_shutdown"
    );

    assert.deepEqual(patches.map((patch) => patch.leaseId), ["lease-a"]);
    assert.equal(patches[0]?.status, "released");
    assert.equal(patches[0]?.releaseReason, "operator_shutdown");
  });
});

function lease(
  id: string,
  taskId: string,
  status: WorkerLeaseRow["status"],
  expiresAt: string
): WorkerLeaseRow {
  return {
    id,
    taskId,
    workerId: "worker-1",
    leaseToken: `${id}-token`,
    status,
    heartbeatAt: "2026-06-26T11:59:30.000Z",
    expiresAt
  };
}
