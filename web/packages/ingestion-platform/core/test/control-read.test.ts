import assert from "node:assert/strict";
import { describe, it } from "node:test";
import type { QueryResult } from "pg";

import {
  loadControlPlaneSnapshot,
  type ControlReadPgClientLike
} from "../src/control-read.js";

const now = "2026-06-27T12:00:00.000Z";

class StubControlClient implements ControlReadPgClientLike {
  constructor(private readonly hasProject: boolean) {}

  async query<T extends Record<string, unknown> = Record<string, unknown>>(
    sql: string
  ): Promise<QueryResult<T>> {
    if (sql.includes("from ingestion_platform.ingestion_projects")) {
      return this.result(this.hasProject ? [{ id: "1" } as unknown as T] : []);
    }
    if (sql.includes("from ingestion_platform.ingestion_worker_leases leases")) {
      return this.result([
        {
          workerId: "worker-1",
          status: "running",
          currentTarget: "FSQ OS Places - Italy",
          heartbeatAt: "2026-06-27T11:59:45.000Z",
          cursor: "fsq.it.0048129"
        } as unknown as T
      ]);
    }
    if (sql.includes("from ingestion_platform.ingestion_targets targets")) {
      return this.result([
        {
          displayName: "FSQ OS Places - Italy",
          adapter: "snapshot",
          safetyMode: "dry_run",
          status: "running",
          workerId: "worker-1",
          checkpoint: "fsq.it.0048129",
          lastSignal: "checkpoint_committed"
        } as unknown as T,
        {
          displayName: "Staging export",
          adapter: "supabase_postgres",
          safetyMode: "approved_write",
          status: "queued",
          workerId: null,
          checkpoint: null,
          lastSignal: null
        } as unknown as T
      ]);
    }
    if (sql.includes("from ingestion_platform.ingestion_events events")) {
      return this.result([
        {
          createdAt: "2026-06-27T11:58:10.000Z",
          signal: "policy_guard_blocked_storage",
          eventType: "policy_blocked",
          message: "Live resolver payload cannot enter reusable cache.",
          severity: "error",
          targetName: "Google rehearsal"
        } as unknown as T
      ]);
    }
    // operational metrics
    return this.result([
      {
        sourceCount: "5",
        promotionTargetCount: "1",
        oldestCheckpointLagSeconds: "94"
      } as unknown as T
    ]);
  }

  private result<T extends Record<string, unknown>>(rows: T[]): QueryResult<T> {
    return { rows, rowCount: rows.length, command: "SELECT", oid: 0, fields: [] } as QueryResult<T>;
  }
}

describe("control-plane read loader", () => {
  it("returns null when the project key does not exist", async () => {
    const snapshot = await loadControlPlaneSnapshot({
      client: new StubControlClient(false),
      projectKey: "missing",
      now
    });
    assert.equal(snapshot, null);
  });

  it("assembles instances, targets, events, and operational metrics", async () => {
    const snapshot = await loadControlPlaneSnapshot({
      client: new StubControlClient(true),
      projectKey: "vamo",
      now
    });

    assert.ok(snapshot);
    assert.equal(snapshot.instances.length, 1);
    assert.equal(snapshot.instances[0]?.id, "worker-1");
    assert.equal(snapshot.instances[0]?.heartbeatSecondsAgo, 15);

    assert.equal(snapshot.targets.length, 2);
    assert.equal(snapshot.targets[1]?.scope, "Promotion stream");
    assert.equal(snapshot.targets[1]?.instanceId, "unassigned");

    assert.equal(snapshot.events[0]?.severity, "error");
    assert.equal(snapshot.events[0]?.time, "11:58:10");

    // 2 targets, 1 approved_write => 1 promotion stream, 1 source seed.
    assert.equal(snapshot.metrics.promotionStreamTargets, 1);
    assert.equal(snapshot.metrics.sourceSeedTargets, 1);
    assert.equal(snapshot.metrics.oldestCheckpointLagSeconds, 94);
    // Cache-business metrics stay zero — the host fills them.
    assert.equal(snapshot.metrics.canonicalsPromoted, 0);
  });
});
