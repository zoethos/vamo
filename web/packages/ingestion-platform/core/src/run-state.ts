import type { IngestionTaskStatus } from "./control-models.js";

export type IngestionCommandKind = "start" | "pause" | "shutdown" | "reset";

export interface CommandTaskRow {
  id: string;
  targetId: string;
  status: IngestionTaskStatus;
  checkpointScope?: string | null;
  workerId?: string | null;
  errorCode?: string | null;
  errorMessage?: string | null;
}

export interface TaskStatusPatch {
  taskId: string;
  previousStatus: IngestionTaskStatus;
  status: IngestionTaskStatus;
  checkpointScope?: string | null;
  preserveCheckpoint: true;
  errorCode?: null;
  errorMessage?: null;
  updatedAt: string;
}

export interface TaskTransitionError {
  code:
    | "invalid_transition"
    | "reset_reason_required"
    | "reset_required";
  taskId: string;
  fromStatus: IngestionTaskStatus;
  command: IngestionCommandKind;
  message: string;
}

export interface TaskTransitionSkipped {
  skipped: true;
  taskId: string;
  status: IngestionTaskStatus;
  command: IngestionCommandKind;
  reason: "already_in_state" | "terminal_state";
}

export type TaskTransitionOutcome =
  | { patch: TaskStatusPatch; error?: never; skipped?: never }
  | { error: TaskTransitionError; patch?: never; skipped?: never }
  | { skipped: TaskTransitionSkipped; patch?: never; error?: never };

export interface PlanTaskTransitionInput {
  task: CommandTaskRow;
  command: IngestionCommandKind;
  now: string;
  reason?: string;
}

export function planTaskCommandTransition(
  input: PlanTaskTransitionInput
): TaskTransitionOutcome {
  const nextStatus = nextTaskStatusForCommand(
    input.task.status,
    input.command,
    input.reason
  );

  if (nextStatus.kind === "error") {
    return {
      error: {
        code: nextStatus.code,
        taskId: input.task.id,
        fromStatus: input.task.status,
        command: input.command,
        message: nextStatus.message
      }
    };
  }

  if (nextStatus.kind === "skip") {
    return {
      skipped: {
        skipped: true,
        taskId: input.task.id,
        status: input.task.status,
        command: input.command,
        reason: nextStatus.reason
      }
    };
  }

  return {
    patch: {
      taskId: input.task.id,
      previousStatus: input.task.status,
      status: nextStatus.status,
      checkpointScope: input.task.checkpointScope ?? null,
      preserveCheckpoint: true,
      ...(input.command === "reset"
        ? {
            errorCode: null,
            errorMessage: null
          }
        : {}),
      updatedAt: input.now
    }
  };
}

function nextTaskStatusForCommand(
  status: IngestionTaskStatus,
  command: IngestionCommandKind,
  reason?: string
):
  | { kind: "transition"; status: IngestionTaskStatus }
  | { kind: "skip"; reason: TaskTransitionSkipped["reason"] }
  | { kind: "error"; code: TaskTransitionError["code"]; message: string } {
  switch (command) {
    case "start":
      if (status === "queued" || status === "paused") {
        return { kind: "transition", status: "running" };
      }
      if (status === "running") {
        return { kind: "skip", reason: "already_in_state" };
      }
      if (status === "failed" || status === "blocked") {
        return {
          kind: "error",
          code: "reset_required",
          message: `Task must be reset before it can start from ${status}.`
        };
      }
      return {
        kind: "skip",
        reason: "terminal_state"
      };

    case "pause":
      if (status === "running" || status === "queued") {
        return { kind: "transition", status: "paused" };
      }
      if (status === "paused") {
        return { kind: "skip", reason: "already_in_state" };
      }
      return {
        kind: "error",
        code: "invalid_transition",
        message: `Cannot pause task from ${status}.`
      };

    case "shutdown":
      if (status === "running" || status === "queued") {
        return { kind: "transition", status: "paused" };
      }
      if (status === "paused") {
        return { kind: "skip", reason: "already_in_state" };
      }
      return {
        kind: "error",
        code: "invalid_transition",
        message: `Cannot shutdown task from ${status}.`
      };

    case "reset":
      if (!reason || reason.trim().length === 0) {
        return {
          kind: "error",
          code: "reset_reason_required",
          message: "Reset requires an operator audit reason."
        };
      }
      if (status === "failed" || status === "blocked") {
        return { kind: "transition", status: "queued" };
      }
      return {
        kind: "error",
        code: "invalid_transition",
        message: `Reset only applies to failed or blocked tasks, not ${status}.`
      };
  }
}
