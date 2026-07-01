"use client";

import { useRouter } from "next/navigation";
import {
  createContext,
  useContext,
  useRef,
  useState,
  type Dispatch,
  type ReactNode,
  type SetStateAction,
} from "react";
import type { AdminRole, AdminAssuranceLevel } from "@confluendo/ingestion-platform/admin-auth";
import type {
  CommandScope,
  IngestionCommandKind,
} from "@confluendo/ingestion-platform/control-api";
import type {
  IngestionAction,
  IngestionTarget,
} from "@confluendo/ingestion-platform/read-model";

type DashboardSource = "live" | "sample";

type CommandResult =
  | { status: "idle" }
  | { status: "confirming"; request: CommandRequest; reason: string }
  | { status: "running"; label: string }
  | { status: "done"; message: string; detail: string }
  | { status: "error"; message: string; detail?: string };

type CommandRequest = {
  label: string;
  command: IngestionCommandKind;
  scope: CommandScope;
  requiresReason?: boolean;
};

type AdminCommandContext = {
  role: AdminRole;
  assuranceLevel: AdminAssuranceLevel;
  source: DashboardSource;
};

export function ClusterCommandControls({
  actions,
  context,
}: {
  actions: IngestionAction[];
  context: AdminCommandContext;
}) {
  const mapped = actions.map((action) => ({
    action,
    request: clusterRequestForAction(action),
  }));

  return (
    <CommandSurface>
      <div className="admin-command-grid">
        {mapped.map(({ action, request }) => (
          <CommandButton
            className={`admin-command admin-command-${action.tone}`}
            context={context}
            key={action.label}
            request={request}
          >
            <span>{action.label}</span>
            <small>{action.detail}</small>
          </CommandButton>
        ))}
      </div>
    </CommandSurface>
  );
}

export function TargetCommandButton({
  context,
  target,
}: {
  context: AdminCommandContext;
  target: IngestionTarget;
}) {
  const request = targetRequest(target);

  return (
    <CommandSurface compact>
      <CommandButton
        className="admin-row-control"
        context={context}
        request={request}
      >
        {target.nextAction}
      </CommandButton>
    </CommandSurface>
  );
}

export function RecoveryCommandButton({
  context,
  target,
}: {
  context: AdminCommandContext;
  target: IngestionTarget;
}) {
  const request: CommandRequest | undefined =
    target.status === "paused" || target.status === "queued"
      ? {
          label: "Resume from checkpoint",
          command: "start",
          scope: { type: "target", targetId: target.id },
        }
      : target.status === "running" || target.status === "complete"
        ? undefined
      : {
          label: "Resume from checkpoint",
          command: "reset",
          scope: { type: "target", targetId: target.id },
          requiresReason: true,
        };

  return (
    <CommandSurface>
      <CommandButton
        className="admin-wide-control"
        context={context}
        request={request}
      >
        Resume from checkpoint
      </CommandButton>
    </CommandSurface>
  );
}

function CommandSurface({
  children,
  compact = false,
}: {
  children: ReactNode;
  compact?: boolean;
}) {
  const [result, setResult] = useState<CommandResult>({ status: "idle" });
  const inFlightRef = useRef(false);
  const router = useRouter();
  const pending = result.status === "running";

  async function runCommand(request: CommandRequest, reason?: string) {
    // Guard against double-submit: ignore re-entry while a command is in flight.
    if (inFlightRef.current) {
      return;
    }
    inFlightRef.current = true;
    setResult({ status: "running", label: request.label });

    try {
      const response = await fetch("/api/admin/ingestion/commands", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          projectKey: "vamo",
          command: request.command,
          scope: request.scope,
          ...(reason ? { reason } : {}),
        }),
      });
      const payload = (await response.json().catch(() => null)) as CommandPayload | null;

      if (!response.ok || !payload || !isCommandResultPayload(payload)) {
        const failure = payload && isCommandFailurePayload(payload) ? payload : undefined;
        const handled = maybeRedirectForAuth(failure);
        if (handled) {
          return;
        }
        setResult({
          status: "error",
          message: failure?.error ?? "Command failed.",
          detail: failure?.code,
        });
        return;
      }

      const applied = payload.appliedTaskPatchIds.length + payload.appliedLeasePatchIds.length;
      const stale = payload.staleTaskPatchIds.length + payload.staleLeasePatchIds.length;
      const warningCount = payload.skipped.length + payload.errors.length + stale;
      setResult({
        status: "done",
        message: payload.ok
          ? `${request.label} accepted`
          : `${request.label} completed with warnings`,
        detail: `${applied} applied, ${payload.skipped.length} skipped, ${payload.errors.length + stale} warnings`,
      });
      router.refresh();

      if (warningCount === 0) {
        window.setTimeout(() => setResult({ status: "idle" }), 3200);
      }
    } catch {
      setResult({ status: "error", message: "Command request failed to send." });
    } finally {
      inFlightRef.current = false;
    }
  }

  function requestConfirmation(request: CommandRequest) {
    setResult({ status: "confirming", request, reason: "" });
  }

  return (
    <CommandSurfaceContext.Provider value={{ runCommand, requestConfirmation, pending }}>
      <div className={compact ? "admin-command-shell admin-command-shell-compact" : "admin-command-shell"}>
        {children}
        <CommandResultView result={result} setResult={setResult} />
      </div>
    </CommandSurfaceContext.Provider>
  );
}

const CommandSurfaceContext = createCommandSurfaceContext();

function CommandButton({
  children,
  className,
  context,
  request,
}: {
  children: ReactNode;
  className: string;
  context: AdminCommandContext;
  request?: CommandRequest;
}) {
  const surface = CommandSurfaceContext.useValue();
  const disabledReason = request ? disabledReasonFor(context, request) : "No command is available for this state.";
  const blockedTitle = disabledReason ?? (surface.pending ? "A command is in progress." : undefined);

  return (
    <button
      className={className}
      type="button"
      disabled={Boolean(disabledReason) || surface.pending}
      title={blockedTitle}
      onClick={() => {
        if (!request) {
          return;
        }
        if (request.requiresReason) {
          surface.requestConfirmation(request);
          return;
        }
        void surface.runCommand(request);
      }}
    >
      {children}
    </button>
  );
}

function CommandResultView({
  result,
  setResult,
}: {
  result: CommandResult;
  setResult: Dispatch<SetStateAction<CommandResult>>;
}) {
  const surface = CommandSurfaceContext.useValue();

  if (result.status === "idle") {
    return null;
  }

  if (result.status === "confirming") {
    return (
      <form
        className="admin-command-confirm"
        onSubmit={(event) => {
          event.preventDefault();
          const reason = result.reason.trim();
          if (!reason) {
            setResult({
              status: "error",
              message: "Reset requires an operator audit reason.",
            });
            return;
          }
          void surface.runCommand(result.request, reason);
        }}
      >
        <label htmlFor="admin-reset-reason">Audit reason</label>
        <textarea
          id="admin-reset-reason"
          value={result.reason}
          onChange={(event) =>
            setResult({ ...result, reason: event.target.value })
          }
          rows={3}
          maxLength={280}
          required
        />
        <div className="admin-command-confirm-actions">
          <button type="submit">Confirm reset</button>
          <button type="button" onClick={() => setResult({ status: "idle" })}>
            Cancel
          </button>
        </div>
      </form>
    );
  }

  if (result.status === "running") {
    return (
      <div className="admin-command-result" role="status">
        {result.label} in progress...
      </div>
    );
  }

  return (
    <div
      className={
        result.status === "error"
          ? "admin-command-result admin-command-result-error"
          : "admin-command-result admin-command-result-ok"
      }
      role={result.status === "error" ? "alert" : "status"}
    >
      <strong>{result.message}</strong>
      {result.detail ? <span>{result.detail}</span> : null}
    </div>
  );
}

function clusterRequestForAction(action: IngestionAction): CommandRequest | undefined {
  switch (action.label) {
    case "Start all":
      return { label: action.label, command: "start", scope: { type: "cluster" } };
    case "Pause all":
      return { label: action.label, command: "pause", scope: { type: "cluster" } };
    case "Shutdown":
      return { label: action.label, command: "shutdown", scope: { type: "cluster" } };
    case "Reset failed":
      return {
        label: action.label,
        command: "reset",
        scope: { type: "cluster" },
        requiresReason: true,
      };
    default:
      return undefined;
  }
}

function targetRequest(target: IngestionTarget): CommandRequest | undefined {
  switch (target.status) {
    case "running":
      return {
        label: "Pause target",
        command: "pause",
        scope: { type: "target", targetId: target.id },
      };
    case "paused":
    case "queued":
      return {
        label: "Start target",
        command: "start",
        scope: { type: "target", targetId: target.id },
      };
    case "blocked":
    case "stopped":
      return {
        label: "Reset target",
        command: "reset",
        scope: { type: "target", targetId: target.id },
        requiresReason: true,
      };
    case "complete":
      return undefined;
  }
}

function disabledReasonFor(
  context: AdminCommandContext,
  request: CommandRequest
): string | undefined {
  if (context.source !== "live") {
    return "Controls require a live control plane.";
  }
  if (context.role === "viewer") {
    return "Viewers can inspect the console but cannot run commands.";
  }
  if (context.assuranceLevel !== "aal2") {
    return "Commands require MFA step-up.";
  }
  if (request.command === "reset" && context.role !== "admin") {
    return "Reset requires the admin role.";
  }
  return undefined;
}

function maybeRedirectForAuth(payload: CommandFailure | undefined): boolean {
  const code = payload?.code;
  const next = encodeURIComponent("/admin/ingestion");
  if (code === "not_authenticated") {
    window.location.assign(`/admin/sign-in?next=${next}`);
    return true;
  }
  if (code === "mfa_enrollment_required") {
    window.location.assign(`/admin/mfa/enroll?next=${next}`);
    return true;
  }
  if (code === "mfa_challenge_required" || code === "fresh_step_up_required") {
    window.location.assign(`/admin/mfa/challenge?reason=${code}&next=${next}`);
    return true;
  }
  return false;
}

type CommandPayload =
  | CommandResultPayload
  | {
      ok: false;
      error: string;
      code?: string;
    };

type CommandFailure = Extract<CommandPayload, { ok: false }>;

function isCommandResultPayload(
  payload: CommandPayload | null
): payload is CommandResultPayload {
  return (
    Boolean(payload) &&
    Array.isArray((payload as Partial<CommandResultPayload>).appliedTaskPatchIds) &&
    Array.isArray((payload as Partial<CommandResultPayload>).appliedLeasePatchIds) &&
    Array.isArray((payload as Partial<CommandResultPayload>).staleTaskPatchIds) &&
    Array.isArray((payload as Partial<CommandResultPayload>).staleLeasePatchIds) &&
    Array.isArray((payload as Partial<CommandResultPayload>).skipped) &&
    Array.isArray((payload as Partial<CommandResultPayload>).errors)
  );
}

function isCommandFailurePayload(payload: CommandPayload): payload is CommandFailure {
  return "error" in payload;
}

type CommandResultPayload = {
  ok: boolean;
  appliedTaskPatchIds: string[];
  appliedLeasePatchIds: string[];
  staleTaskPatchIds: string[];
  staleLeasePatchIds: string[];
  skipped: unknown[];
  errors: unknown[];
};

function createCommandSurfaceContext() {
  const context = createContext<{
    runCommand: (request: CommandRequest, reason?: string) => Promise<void>;
    requestConfirmation: (request: CommandRequest) => void;
    pending: boolean;
  } | null>(null);

  return {
    Provider: context.Provider,
    useValue() {
      const value = useContext(context);
      if (!value) {
        throw new Error("Command controls must render inside CommandSurface.");
      }
      return value;
    },
  };
}
