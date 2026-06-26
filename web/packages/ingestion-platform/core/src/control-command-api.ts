import { Client, type QueryResult } from "pg";

import {
  planIngestionCommand,
  type CommandActor,
  type CommandScope,
  type CommandStateSnapshot,
  type IngestionCommandAuditEvent,
  type IngestionCommandPlan
} from "./commands.js";
import type { IngestionTaskStatus } from "./control-models.js";
import type { WorkerLeasePatch, WorkerLeaseRow, WorkerLeaseStatus } from "./leases.js";
import type { IngestionCommandKind, TaskStatusPatch } from "./run-state.js";

export type { CommandActor, CommandScope } from "./commands.js";
export type { IngestionCommandKind } from "./run-state.js";

export interface ControlCommandPgClientLike {
  query<T extends Record<string, unknown> = Record<string, unknown>>(
    sql: string,
    values?: unknown[]
  ): Promise<QueryResult<T>>;
}

export interface ApplyPostgresIngestionCommandInput {
  connectionString?: string;
  client?: ControlCommandPgClientLike;
  projectId?: string | number;
  projectKey?: string;
  command: IngestionCommandKind;
  scope: CommandScope;
  actor: CommandActor;
  now?: string;
  reason?: string;
  /**
   * Operator label the caller *claims*. Recorded in the audit payload for
   * forensics only — never trusted as the authenticated actor. The trusted
   * identity is `actor`, set by the server-side caller.
   */
  claimedActorId?: string;
  /**
   * Non-sensitive, server-derived authorization context to preserve alongside
   * command audit rows. Never include tokens, cookies, or raw JWTs.
   */
  auditContext?: Record<string, unknown>;
}

export interface AppliedPostgresIngestionCommandResult {
  ok: boolean;
  plan: IngestionCommandPlan;
  appliedTaskPatchIds: string[];
  appliedLeasePatchIds: string[];
  staleTaskPatchIds: string[];
  staleLeasePatchIds: string[];
}

interface ProjectRow extends Record<string, unknown> {
  id: string;
  projectKey: string;
}

interface TaskRow extends Record<string, unknown> {
  id: string;
  targetId: string | null;
  status: IngestionTaskStatus;
  checkpointScope: string | null;
  errorCode: string | null;
  errorMessage: string | null;
}

interface LeaseRow extends Record<string, unknown> {
  id: string;
  taskId: string;
  workerId: string;
  leaseToken: string;
  status: WorkerLeaseStatus;
  heartbeatAt: string | Date;
  expiresAt: string | Date;
  releasedAt?: string | Date | null;
  releaseReason?: string | null;
}

export async function applyPostgresIngestionCommand(
  input: ApplyPostgresIngestionCommandInput
): Promise<AppliedPostgresIngestionCommandResult> {
  if (!input.client && !input.connectionString) {
    throw new Error("Ingestion command API requires a server-side connection string or client.");
  }

  const ownedClient = input.client ? undefined : new Client({ connectionString: input.connectionString });
  const client = input.client ?? ownedClient;
  if (!client) {
    throw new Error("Ingestion command API client could not be initialized.");
  }

  if (ownedClient) {
    await ownedClient.connect();
  }

  try {
    await client.query("begin");
    await client.query("set local statement_timeout = '5s'");

    const project = await resolveProject(client, input);
    const snapshot = await loadCommandStateSnapshot(client, project);
    const now = input.now ?? new Date().toISOString();
    const plan = planIngestionCommand(snapshot, {
      command: input.command,
      scope: input.scope,
      actor: input.actor,
      now,
      reason: input.reason
    });

    const appliedTaskPatchIds: string[] = [];
    const staleTaskPatchIds: string[] = [];
    const appliedLeasePatchIds: string[] = [];
    const staleLeasePatchIds: string[] = [];

    if (plan.ok) {
      for (const patch of sortTaskPatches(plan.taskPatches)) {
        const applied = await applyTaskPatch(client, patch);
        if (applied) {
          appliedTaskPatchIds.push(patch.taskId);
        } else {
          staleTaskPatchIds.push(patch.taskId);
        }
      }

      for (const patch of sortLeasePatches(plan.leasePatches)) {
        const applied = await applyLeasePatch(client, patch);
        if (applied) {
          appliedLeasePatchIds.push(patch.leaseId);
        } else {
          staleLeasePatchIds.push(patch.leaseId);
        }
      }
    }

    const ok =
      plan.ok &&
      staleTaskPatchIds.length === 0 &&
      staleLeasePatchIds.length === 0;

    await insertAuditEvent(client, project.id, plan.auditEvent, {
      ...plan.auditEvent.payload,
      accepted: ok,
      appliedTaskPatchIds,
      appliedLeasePatchIds,
      staleTaskPatchIds,
      staleLeasePatchIds,
      ...(input.claimedActorId ? { claimedActorId: input.claimedActorId } : {}),
      ...(input.auditContext ? { adminPrincipal: input.auditContext } : {})
    });

    await client.query("commit");

    return {
      ok,
      plan,
      appliedTaskPatchIds,
      appliedLeasePatchIds,
      staleTaskPatchIds,
      staleLeasePatchIds
    };
  } catch (error) {
    await client.query("rollback");
    throw error;
  } finally {
    if (ownedClient) {
      await ownedClient.end();
    }
  }
}

async function resolveProject(
  client: ControlCommandPgClientLike,
  input: Pick<ApplyPostgresIngestionCommandInput, "projectId" | "projectKey">
): Promise<ProjectRow> {
  if (input.projectId !== undefined) {
    const result = await client.query<ProjectRow>(
      `
        select id::text as id, project_key as "projectKey"
        from ingestion_platform.ingestion_projects
        where id = $1::bigint
      `,
      [String(input.projectId)]
    );
    return requireProject(result);
  }

  if (input.projectKey) {
    const result = await client.query<ProjectRow>(
      `
        select id::text as id, project_key as "projectKey"
        from ingestion_platform.ingestion_projects
        where project_key = $1
      `,
      [input.projectKey]
    );
    return requireProject(result);
  }

  throw new Error("Ingestion command API requires projectId or projectKey.");
}

function requireProject(result: QueryResult<ProjectRow>): ProjectRow {
  const project = result.rows[0];
  if (!project) {
    throw new Error("Ingestion project was not found.");
  }
  return project;
}

async function loadCommandStateSnapshot(
  client: ControlCommandPgClientLike,
  project: ProjectRow
): Promise<CommandStateSnapshot> {
  const tasks = await client.query<TaskRow>(
    `
      select
        id::text as id,
        target_id::text as "targetId",
        status,
        checkpoint_scope as "checkpointScope",
        error_code as "errorCode",
        error_message as "errorMessage"
      from ingestion_platform.ingestion_tasks
      where project_id = $1::bigint
      order by id
      for update
    `,
    [project.id]
  );
  const leases = await client.query<LeaseRow>(
    `
      select
        leases.id::text as id,
        leases.task_id::text as "taskId",
        leases.worker_id as "workerId",
        leases.lease_token as "leaseToken",
        leases.status,
        leases.heartbeat_at as "heartbeatAt",
        leases.expires_at as "expiresAt",
        leases.released_at as "releasedAt",
        leases.release_reason as "releaseReason"
      from ingestion_platform.ingestion_worker_leases leases
      join ingestion_platform.ingestion_tasks tasks
        on tasks.id = leases.task_id
      where tasks.project_id = $1::bigint
      order by leases.id
      for update of leases
    `,
    [project.id]
  );

  return {
    projectId: project.projectKey,
    tasks: tasks.rows.map((task) => ({
      id: task.id,
      targetId: task.targetId ?? "",
      status: task.status,
      checkpointScope: task.checkpointScope,
      errorCode: task.errorCode,
      errorMessage: task.errorMessage
    })),
    leases: leases.rows.map(toWorkerLeaseRow)
  };
}

function toWorkerLeaseRow(row: LeaseRow): WorkerLeaseRow {
  return {
    id: row.id,
    taskId: row.taskId,
    workerId: row.workerId,
    leaseToken: row.leaseToken,
    status: row.status,
    heartbeatAt: toIsoString(row.heartbeatAt),
    expiresAt: toIsoString(row.expiresAt),
    releasedAt: row.releasedAt ? toIsoString(row.releasedAt) : null,
    releaseReason: row.releaseReason ?? null
  };
}

async function applyTaskPatch(
  client: ControlCommandPgClientLike,
  patch: TaskStatusPatch
): Promise<boolean> {
  const clearsError = Object.prototype.hasOwnProperty.call(patch, "errorCode");
  const result = await client.query<{ id: string }>(
    `
      update ingestion_platform.ingestion_tasks
      set
        status = $1,
        error_code = case when $2::boolean then null else error_code end,
        error_message = case when $2::boolean then null else error_message end,
        started_at = case
          when $1 = 'running' and started_at is null then $3::timestamptz
          else started_at
        end,
        updated_at = $3::timestamptz
      where id = $4::bigint
        and status = $5
      returning id::text as id
    `,
    [patch.status, clearsError, patch.updatedAt, patch.taskId, patch.previousStatus]
  );

  return result.rowCount === 1;
}

async function applyLeasePatch(
  client: ControlCommandPgClientLike,
  patch: WorkerLeasePatch
): Promise<boolean> {
  const result = await client.query<{ id: string }>(
    `
      update ingestion_platform.ingestion_worker_leases
      set
        status = $1,
        released_at = $2::timestamptz,
        release_reason = $3
      where id = $4::bigint
        and status = $5
      returning id::text as id
    `,
    [patch.status, patch.releasedAt, patch.releaseReason, patch.leaseId, patch.previousStatus]
  );

  return result.rowCount === 1;
}

async function insertAuditEvent(
  client: ControlCommandPgClientLike,
  projectId: string,
  event: IngestionCommandAuditEvent,
  payload: Record<string, unknown>
): Promise<void> {
  await client.query(
    `
      insert into ingestion_platform.ingestion_audit_log (
        project_id,
        actor_type,
        actor_id,
        action,
        target_type,
        target_id,
        reason,
        payload,
        created_at
      )
      values (
        $1::bigint,
        $2,
        $3,
        $4,
        $5,
        $6,
        $7,
        $8::jsonb,
        $9::timestamptz
      )
    `,
    [
      projectId,
      event.actorType,
      event.actorId ?? null,
      event.action,
      event.targetType,
      event.targetId ?? null,
      event.reason ?? null,
      JSON.stringify(payload),
      event.createdAt
    ]
  );
}

function sortTaskPatches(patches: TaskStatusPatch[]): TaskStatusPatch[] {
  return [...patches].sort((a, b) => compareIds(a.taskId, b.taskId));
}

function sortLeasePatches(patches: WorkerLeasePatch[]): WorkerLeasePatch[] {
  return [...patches].sort((a, b) => compareIds(a.leaseId, b.leaseId));
}

function compareIds(left: string, right: string): number {
  const leftNumber = Number(left);
  const rightNumber = Number(right);
  if (Number.isFinite(leftNumber) && Number.isFinite(rightNumber)) {
    return leftNumber - rightNumber;
  }
  return left.localeCompare(right);
}

function toIsoString(value: string | Date): string {
  return value instanceof Date ? value.toISOString() : value;
}
