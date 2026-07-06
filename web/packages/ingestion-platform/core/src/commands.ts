import {
  releaseActiveLeasesForTasks,
  type WorkerLeasePatch,
  type WorkerLeaseRow
} from "./leases.js";
import {
  planTaskCommandTransition,
  type CommandTaskRow,
  type IngestionCommandKind,
  type TaskStatusPatch,
  type TaskTransitionError,
  type TaskTransitionSkipped
} from "./run-state.js";

/**
 * `autonomous_agent` is not a broad machine token. Its authority is limited to an
 * active autonomy policy envelope, standing platform guards, still-valid human
 * approvals when required, and idempotent ledger state.
 */
export type CommandActorType =
  | "operator"
  | "system"
  | "worker"
  | "api"
  | "autonomous_agent";

export interface CommandActor {
  type: CommandActorType;
  id?: string;
}

export type CommandScope =
  | { type: "cluster" }
  | { type: "target"; targetId: string }
  | { type: "task"; taskId: string }
  | { type: "worker"; workerId: string };

export interface CommandStateSnapshot {
  projectId?: string;
  tasks: CommandTaskRow[];
  leases: WorkerLeaseRow[];
}

export interface IngestionCommandInput {
  command: IngestionCommandKind;
  scope: CommandScope;
  actor: CommandActor;
  now: string;
  reason?: string;
}

export interface IngestionCommandError {
  code:
    | "reset_reason_required"
    | "no_matching_tasks"
    | "no_eligible_tasks"
    | TaskTransitionError["code"];
  taskId?: string;
  message: string;
}

export interface IngestionCommandAuditEvent {
  projectId?: string;
  actorType: CommandActorType;
  actorId?: string;
  action: `ingestion.${IngestionCommandKind}`;
  targetType: CommandScope["type"];
  targetId?: string;
  reason?: string;
  createdAt: string;
  payload: {
    accepted: boolean;
    command: IngestionCommandKind;
    scope: CommandScope;
    changedTaskIds: string[];
    leaseIds: string[];
    skipped: TaskTransitionSkipped[];
    errors: IngestionCommandError[];
  };
}

export interface IngestionCommandPlan {
  ok: boolean;
  taskPatches: TaskStatusPatch[];
  leasePatches: WorkerLeasePatch[];
  skipped: TaskTransitionSkipped[];
  errors: IngestionCommandError[];
  auditEvent: IngestionCommandAuditEvent;
}

export function planIngestionCommand(
  snapshot: CommandStateSnapshot,
  input: IngestionCommandInput
): IngestionCommandPlan {
  const resetReasonError = validateCommandInput(input);
  if (resetReasonError) {
    return buildPlan(snapshot, input, [], [], [], [resetReasonError]);
  }

  const selectedTasks = selectScopedTasks(snapshot, input.scope);
  if (selectedTasks.length === 0) {
    return buildPlan(snapshot, input, [], [], [], [
      {
        code: "no_matching_tasks",
        message: "Command scope did not match any tasks."
      }
    ]);
  }

  const taskPatches: TaskStatusPatch[] = [];
  const skipped: TaskTransitionSkipped[] = [];
  const errors: IngestionCommandError[] = [];

  for (const task of selectedTasks) {
    const outcome = planTaskCommandTransition({
      task,
      command: input.command,
      now: input.now,
      reason: input.reason
    });

    if (outcome.patch) {
      taskPatches.push(outcome.patch);
    } else if (outcome.skipped) {
      skipped.push(outcome.skipped);
    } else {
      errors.push({
        code: outcome.error.code,
        taskId: outcome.error.taskId,
        message: outcome.error.message
      });
    }
  }

  const selectedTaskIds = new Set(selectedTasks.map((task) => task.id));
  const changedTaskIds = new Set(taskPatches.map((patch) => patch.taskId));
  const leasePatches = planLeasePatches(snapshot, input, selectedTaskIds, changedTaskIds);

  if (
    taskPatches.length === 0 &&
    leasePatches.length === 0 &&
    skipped.length === 0 &&
    errors.length === 0
  ) {
    errors.push({
      code: "no_eligible_tasks",
      message: "Command scope matched tasks, but none were eligible for the requested transition."
    });
  }

  const changed = taskPatches.length > 0 || leasePatches.length > 0;
  const benignNoop = !changed && skipped.length > 0 && errors.length === 0;
  const ok = changed || benignNoop;

  return buildPlan(snapshot, input, taskPatches, leasePatches, skipped, errors, ok);
}

function validateCommandInput(input: IngestionCommandInput): IngestionCommandError | undefined {
  if (input.command !== "reset") {
    return undefined;
  }

  if (input.reason && input.reason.trim().length > 0) {
    return undefined;
  }

  return {
    code: "reset_reason_required",
    message: "Reset requires an operator audit reason."
  };
}

function selectScopedTasks(
  snapshot: CommandStateSnapshot,
  scope: CommandScope
): CommandTaskRow[] {
  if (scope.type === "cluster") {
    return snapshot.tasks;
  }

  if (scope.type === "target") {
    return snapshot.tasks.filter((task) => task.targetId === scope.targetId);
  }

  if (scope.type === "task") {
    return snapshot.tasks.filter((task) => task.id === scope.taskId);
  }

  const leasedTaskIds = new Set(
    snapshot.leases
      .filter((lease) => lease.workerId === scope.workerId && lease.status === "active")
      .map((lease) => lease.taskId)
  );
  return snapshot.tasks.filter(
    (task) => task.workerId === scope.workerId || leasedTaskIds.has(task.id)
  );
}

function planLeasePatches(
  snapshot: CommandStateSnapshot,
  input: IngestionCommandInput,
  selectedTaskIds: ReadonlySet<string>,
  changedTaskIds: ReadonlySet<string>
): WorkerLeasePatch[] {
  if (input.command === "shutdown") {
    return releaseActiveLeasesForTasks(
      snapshot.leases,
      selectedTaskIds,
      input.now,
      "operator_shutdown"
    );
  }

  if (input.command === "reset") {
    return releaseActiveLeasesForTasks(
      snapshot.leases,
      changedTaskIds,
      input.now,
      "operator_reset"
    );
  }

  return [];
}

function buildPlan(
  snapshot: CommandStateSnapshot,
  input: IngestionCommandInput,
  taskPatches: TaskStatusPatch[],
  leasePatches: WorkerLeasePatch[],
  skipped: TaskTransitionSkipped[],
  errors: IngestionCommandError[],
  forcedOk?: boolean
): IngestionCommandPlan {
  const ok = forcedOk ?? errors.length === 0;
  const auditEvent = buildAuditEvent(snapshot, input, ok, taskPatches, leasePatches, skipped, errors);

  return {
    ok,
    taskPatches,
    leasePatches,
    skipped,
    errors,
    auditEvent
  };
}

function buildAuditEvent(
  snapshot: CommandStateSnapshot,
  input: IngestionCommandInput,
  accepted: boolean,
  taskPatches: TaskStatusPatch[],
  leasePatches: WorkerLeasePatch[],
  skipped: TaskTransitionSkipped[],
  errors: IngestionCommandError[]
): IngestionCommandAuditEvent {
  return {
    projectId: snapshot.projectId,
    actorType: input.actor.type,
    actorId: input.actor.id,
    action: `ingestion.${input.command}`,
    targetType: input.scope.type,
    targetId: commandScopeId(input.scope),
    reason: input.reason,
    createdAt: input.now,
    payload: {
      accepted,
      command: input.command,
      scope: input.scope,
      changedTaskIds: taskPatches.map((patch) => patch.taskId),
      leaseIds: leasePatches.map((patch) => patch.leaseId),
      skipped,
      errors
    }
  };
}

function commandScopeId(scope: CommandScope): string | undefined {
  switch (scope.type) {
    case "cluster":
      return undefined;
    case "target":
      return scope.targetId;
    case "task":
      return scope.taskId;
    case "worker":
      return scope.workerId;
  }
}
