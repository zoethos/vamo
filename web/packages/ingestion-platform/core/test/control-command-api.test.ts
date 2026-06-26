import assert from "node:assert/strict";
import { describe, it } from "node:test";
import type { QueryResult } from "pg";

import {
  applyPostgresIngestionCommand,
  type ControlCommandPgClientLike
} from "../src/control-command-api.js";
import type { IngestionTaskStatus } from "../src/control-models.js";
import type { WorkerLeaseStatus } from "../src/leases.js";

const now = "2026-06-26T12:00:00.000Z";
const actor = { type: "operator" as const, id: "founder" };

describe("postgres ingestion command API", () => {
  it("applies a scoped start command and writes an accepted audit event", async () => {
    const client = new MemoryControlClient({
      tasks: [
        task("100", "10", "queued"),
        task("101", "11", "queued")
      ]
    });

    const result = await applyPostgresIngestionCommand({
      client,
      projectKey: "vamo",
      command: "start",
      scope: { type: "target", targetId: "10" },
      actor,
      now
    });

    assert.equal(result.ok, true);
    assert.deepEqual(result.appliedTaskPatchIds, ["100"]);
    assert.equal(client.task("100").status, "running");
    assert.equal(client.task("101").status, "queued");
    assert.equal(client.audits.length, 1);
    assert.equal(client.audits[0]?.action, "ingestion.start");
    assert.equal(client.audits[0]?.payload.accepted, true);
    assert.deepEqual(client.audits[0]?.payload.appliedTaskPatchIds, ["100"]);
  });

  it("writes a rejected audit event when reset has no operator reason", async () => {
    const client = new MemoryControlClient({
      tasks: [task("100", "10", "failed", "fixture_error", "needs review")]
    });

    const result = await applyPostgresIngestionCommand({
      client,
      projectKey: "vamo",
      command: "reset",
      scope: { type: "target", targetId: "10" },
      actor,
      now
    });

    assert.equal(result.ok, false);
    assert.equal(client.task("100").status, "failed");
    assert.equal(client.audits.length, 1);
    assert.equal(client.audits[0]?.payload.accepted, false);
    assert.equal(client.audits[0]?.payload.errors[0]?.code, "reset_reason_required");
  });

  it("releases scoped active leases on shutdown", async () => {
    const client = new MemoryControlClient({
      tasks: [task("100", "10", "running")],
      leases: [lease("200", "100", "worker-1")]
    });

    const result = await applyPostgresIngestionCommand({
      client,
      projectKey: "vamo",
      command: "shutdown",
      scope: { type: "worker", workerId: "worker-1" },
      actor,
      now
    });

    assert.equal(result.ok, true);
    assert.equal(client.task("100").status, "paused");
    assert.equal(client.lease("200").status, "released");
    assert.equal(client.lease("200").releaseReason, "operator_shutdown");
    assert.deepEqual(client.audits[0]?.payload.appliedLeasePatchIds, ["200"]);
  });

  it("records a claimed actor id in the payload but never as the trusted actor", async () => {
    const client = new MemoryControlClient({
      tasks: [task("100", "10", "queued")]
    });

    const result = await applyPostgresIngestionCommand({
      client,
      projectKey: "vamo",
      command: "start",
      scope: { type: "target", targetId: "10" },
      actor: { type: "api", id: "admin-api" },
      claimedActorId: "not-really-the-founder",
      now
    });

    assert.equal(result.ok, true);
    // Trusted actor on the audit row is the server identity, not the claim.
    assert.equal(client.audits[0]?.actorId, "admin-api");
    // The claim is preserved for forensics, clearly separated in the payload.
    assert.equal(client.audits[0]?.payload.claimedActorId, "not-really-the-founder");
  });

  it("does not clobber a stale task status and reports the stale patch in audit payload", async () => {
    const client = new MemoryControlClient({
      tasks: [task("100", "10", "queued")],
      staleTaskIds: ["100"]
    });

    const result = await applyPostgresIngestionCommand({
      client,
      projectKey: "vamo",
      command: "start",
      scope: { type: "target", targetId: "10" },
      actor,
      now
    });

    assert.equal(result.ok, false);
    assert.equal(client.task("100").status, "queued");
    assert.deepEqual(result.staleTaskPatchIds, ["100"]);
    assert.equal(client.audits[0]?.payload.accepted, false);
    assert.deepEqual(client.audits[0]?.payload.staleTaskPatchIds, ["100"]);
  });

  it("accepts idempotent no-op commands and records skipped tasks", async () => {
    const client = new MemoryControlClient({
      tasks: [
        task("100", "10", "running"),
        task("101", "10", "running")
      ]
    });

    const result = await applyPostgresIngestionCommand({
      client,
      projectKey: "vamo",
      command: "start",
      scope: { type: "target", targetId: "10" },
      actor,
      now
    });

    assert.equal(result.ok, true);
    assert.equal(result.appliedTaskPatchIds.length, 0);
    assert.equal(result.plan.skipped.length, 2);
    assert.equal(client.task("100").status, "running");
    assert.equal(client.audits[0]?.payload.accepted, true);
    assert.equal(client.audits[0]?.payload.errors.length, 0);
    assert.equal(client.audits[0]?.payload.skipped.length, 2);
  });

  it("applies partial success and leaves transition errors in the audit payload", async () => {
    const client = new MemoryControlClient({
      tasks: [
        task("100", "10", "running"),
        task("101", "10", "succeeded")
      ]
    });

    const result = await applyPostgresIngestionCommand({
      client,
      projectKey: "vamo",
      command: "pause",
      scope: { type: "target", targetId: "10" },
      actor,
      now
    });

    assert.equal(result.ok, true);
    assert.deepEqual(result.appliedTaskPatchIds, ["100"]);
    assert.equal(client.task("100").status, "paused");
    assert.equal(client.task("101").status, "succeeded");
    assert.equal(client.audits[0]?.payload.accepted, true);
    assert.equal(client.audits[0]?.payload.errors[0]?.code, "invalid_transition");
    assert.equal(client.audits[0]?.payload.errors[0]?.taskId, "101");
  });
});

interface MemoryTask {
  id: string;
  targetId: string;
  status: IngestionTaskStatus;
  checkpointScope: string | null;
  errorCode: string | null;
  errorMessage: string | null;
}

interface MemoryLease {
  id: string;
  taskId: string;
  workerId: string;
  leaseToken: string;
  status: WorkerLeaseStatus;
  heartbeatAt: string;
  expiresAt: string;
  releasedAt: string | null;
  releaseReason: string | null;
}

interface MemoryAudit {
  action: string;
  actorId: string | null;
  payload: Record<string, any>;
}

class MemoryControlClient implements ControlCommandPgClientLike {
  readonly audits: MemoryAudit[] = [];
  private readonly tasksById = new Map<string, MemoryTask>();
  private readonly leasesById = new Map<string, MemoryLease>();
  private readonly staleTaskIds: Set<string>;

  constructor(input: {
    tasks: MemoryTask[];
    leases?: MemoryLease[];
    staleTaskIds?: string[];
  }) {
    for (const memoryTask of input.tasks) {
      this.tasksById.set(memoryTask.id, { ...memoryTask });
    }
    for (const memoryLease of input.leases ?? []) {
      this.leasesById.set(memoryLease.id, { ...memoryLease });
    }
    this.staleTaskIds = new Set(input.staleTaskIds ?? []);
  }

  task(id: string): MemoryTask {
    const memoryTask = this.tasksById.get(id);
    assert.ok(memoryTask);
    return memoryTask;
  }

  lease(id: string): MemoryLease {
    const memoryLease = this.leasesById.get(id);
    assert.ok(memoryLease);
    return memoryLease;
  }

  async query<T extends Record<string, unknown> = Record<string, unknown>>(
    sql: string,
    values: unknown[] = []
  ): Promise<QueryResult<T>> {
    if (sql === "begin" || sql === "commit" || sql === "rollback" || sql.startsWith("set local")) {
      return this.result([]);
    }

    if (sql.includes("insert into ingestion_platform.ingestion_audit_log")) {
      this.audits.push({
        action: String(values[3]),
        actorId: values[2] == null ? null : String(values[2]),
        payload: JSON.parse(String(values[7])) as Record<string, any>
      });
      return this.result([]);
    }

    if (sql.includes("from ingestion_platform.ingestion_projects")) {
      return this.result([{ id: "1", projectKey: "vamo" } as unknown as T]);
    }

    if (
      sql.includes("from ingestion_platform.ingestion_tasks") &&
      sql.includes("for update") &&
      !sql.includes("join ingestion_platform.ingestion_tasks")
    ) {
      return this.result(
        [...this.tasksById.values()]
          .sort((left, right) => Number(left.id) - Number(right.id))
          .map((memoryTask) => ({
            id: memoryTask.id,
            targetId: memoryTask.targetId,
            status: memoryTask.status,
            checkpointScope: memoryTask.checkpointScope,
            errorCode: memoryTask.errorCode,
            errorMessage: memoryTask.errorMessage
          }) as unknown as T)
      );
    }

    if (sql.includes("from ingestion_platform.ingestion_worker_leases leases")) {
      return this.result(
        [...this.leasesById.values()]
          .sort((left, right) => Number(left.id) - Number(right.id))
          .map((memoryLease) => ({ ...memoryLease }) as unknown as T)
      );
    }

    if (sql.includes("update ingestion_platform.ingestion_tasks")) {
      const [status, clearsError, updatedAt, taskId, previousStatus] = values;
      const memoryTask = this.tasksById.get(String(taskId));
      if (
        !memoryTask ||
        memoryTask.status !== previousStatus ||
        this.staleTaskIds.has(memoryTask.id)
      ) {
        return this.result([], 0);
      }

      memoryTask.status = status as IngestionTaskStatus;
      if (clearsError) {
        memoryTask.errorCode = null;
        memoryTask.errorMessage = null;
      }
      assert.equal(typeof updatedAt, "string");
      return this.result([{ id: memoryTask.id } as unknown as T]);
    }

    if (sql.includes("update ingestion_platform.ingestion_worker_leases")) {
      const [status, releasedAt, releaseReason, leaseId, previousStatus] = values;
      const memoryLease = this.leasesById.get(String(leaseId));
      if (!memoryLease || memoryLease.status !== previousStatus) {
        return this.result([], 0);
      }

      memoryLease.status = status as WorkerLeaseStatus;
      memoryLease.releasedAt = String(releasedAt);
      memoryLease.releaseReason = String(releaseReason);
      return this.result([{ id: memoryLease.id } as unknown as T]);
    }

    throw new Error(`Unhandled SQL in memory control client: ${sql}`);
  }

  private result<T extends Record<string, unknown>>(
    rows: T[],
    rowCount = rows.length
  ): QueryResult<T> {
    return {
      rows,
      rowCount,
      command: "SELECT",
      oid: 0,
      fields: []
    } as QueryResult<T>;
  }
}

function task(
  id: string,
  targetId: string,
  status: IngestionTaskStatus,
  errorCode: string | null = null,
  errorMessage: string | null = null
): MemoryTask {
  return {
    id,
    targetId,
    status,
    checkpointScope: `${targetId}.cursor`,
    errorCode,
    errorMessage
  };
}

function lease(id: string, taskId: string, workerId: string): MemoryLease {
  return {
    id,
    taskId,
    workerId,
    leaseToken: `${id}-token`,
    status: "active",
    heartbeatAt: "2026-06-26T11:59:30.000Z",
    expiresAt: "2026-06-26T12:01:00.000Z",
    releasedAt: null,
    releaseReason: null
  };
}
