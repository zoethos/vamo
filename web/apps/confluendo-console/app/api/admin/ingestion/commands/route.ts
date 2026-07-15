import { timingSafeEqual } from "node:crypto";

import { NextResponse, type NextRequest } from "next/server";
import {
  applyPostgresIngestionCommand,
  type CommandScope,
  type IngestionCommandKind
} from "@confluendo/ingestion-platform/control-api";
import { authorizeMachineCommand } from "@confluendo/ingestion-platform/admin-auth";
import { authorizeIngestionCommandRequest } from "@/lib/ingestion-admin-auth";
import { getActiveControlEnvironmentConfig } from "@/lib/control-environment-server";

export const runtime = "nodejs";

const commandKinds = new Set(["start", "pause", "shutdown", "reset"]);

// Constant-time bearer comparison so request timing cannot leak the token.
function bearerTokenMatches(header: string | null, token: string): boolean {
  if (!header) {
    return false;
  }
  const expected = Buffer.from(`Bearer ${token}`);
  const provided = Buffer.from(header);
  // Length is not the secret; the guard is required because timingSafeEqual
  // throws on differing buffer lengths.
  if (provided.length !== expected.length) {
    return false;
  }
  return timingSafeEqual(provided, expected);
}

export async function POST(request: NextRequest) {
  const body = await readJsonBody(request);
  if (!body.ok) {
    return NextResponse.json({ ok: false, error: body.error }, { status: 400 });
  }

  const parsed = parseCommandRequest(body.value);
  if (!parsed.ok) {
    return NextResponse.json({ ok: false, error: parsed.error }, { status: 400 });
  }

  const auth = await resolveCommandAuth(request, parsed.command, parsed.projectKey ?? "vamo");
  if (!auth.ok) {
    return NextResponse.json(auth.body, { status: auth.status });
  }

  const connectionString = (await getActiveControlEnvironmentConfig())?.controlDatabaseUrl;
  if (!connectionString) {
    return NextResponse.json(
      { ok: false, error: "Ingestion control database URL is not configured." },
      { status: 503 }
    );
  }

  const result = await applyCommand({
    connectionString,
    projectId: parsed.projectId,
    projectKey: parsed.projectKey ?? "vamo",
    command: parsed.command,
    scope: parsed.scope,
    actor: auth.actor,
    auditContext: auth.auditContext,
    claimedActorId: parsed.claimedActorId,
    reason: parsed.reason
  });

  if (!result.ok) {
    return NextResponse.json(result.body, { status: result.status });
  }

  const commandResult = result.value;

  return NextResponse.json({
    ok: commandResult.ok,
    command: parsed.command,
    scope: parsed.scope,
    appliedTaskPatchIds: commandResult.appliedTaskPatchIds,
    appliedLeasePatchIds: commandResult.appliedLeasePatchIds,
    staleTaskPatchIds: commandResult.staleTaskPatchIds,
    staleLeasePatchIds: commandResult.staleLeasePatchIds,
    skipped: commandResult.plan.skipped,
    errors: commandResult.plan.errors
  });
}

async function applyCommand(input: {
  connectionString: string;
  projectId?: string | number;
  projectKey: string;
  command: IngestionCommandKind;
  scope: CommandScope;
  actor: { type: "operator" | "api"; id: string };
  auditContext?: Record<string, unknown>;
  claimedActorId?: string;
  reason?: string;
}): Promise<
  | { ok: true; value: Awaited<ReturnType<typeof applyPostgresIngestionCommand>> }
  | { ok: false; status: number; body: { ok: false; error: string } }
> {
  try {
    return {
      ok: true,
      value: await applyPostgresIngestionCommand({
        connectionString: input.connectionString,
        projectId: input.projectId,
        projectKey: input.projectKey,
        command: input.command,
        scope: input.scope,
        actor: input.actor,
        claimedActorId: input.claimedActorId,
        auditContext: input.auditContext,
        reason: input.reason
      })
    };
  } catch (error) {
    const isProjectNotFound = error instanceof Error && error.message.includes("project was not found");
    if (!isProjectNotFound) {
      console.error("Ingestion command API failed", error);
    }

    return {
      ok: false,
      status: isProjectNotFound ? 404 : 500,
      body: {
        ok: false,
        error: isProjectNotFound ? "Ingestion project not found." : "Ingestion command failed."
      }
    };
  }
}

async function resolveCommandAuth(
  request: NextRequest,
  command: IngestionCommandKind,
  projectKey: string
): Promise<
  | {
      ok: true;
      actor: { type: "operator" | "api"; id: string };
      auditContext?: Record<string, unknown>;
    }
  | { ok: false; status: number; body: { ok: false; error: string; code?: string } }
> {
  const authorization = request.headers.get("authorization");
  if (authorization) {
    const adminToken = (await getActiveControlEnvironmentConfig())?.ingestionAdminApiToken;
    if (!adminToken) {
      return {
        ok: false,
        status: 503,
        body: {
          ok: false,
          code: "machine_token_not_configured",
          error: "Ingestion admin API token is not configured."
        }
      };
    }

    if (!bearerTokenMatches(authorization, adminToken)) {
      return {
        ok: false,
        status: 401,
        body: { ok: false, code: "unauthorized", error: "Unauthorized." }
      };
    }

    // The machine token is never a substitute for an MFA-gated admin session:
    // destructive commands (reset, shutdown) are denied on the token path and
    // require an authenticated admin with aal2 + fresh step-up.
    const machine = authorizeMachineCommand(command);
    if (!machine.ok) {
      return {
        ok: false,
        status: 403,
        body: {
          ok: false,
          code: machine.code,
          error:
            "The machine token cannot run this command. Reset and shutdown require an authenticated admin session with MFA."
        }
      };
    }

    return {
      ok: true,
      actor: {
        type: "api",
        id: "admin-api"
      }
    };
  }

  return authorizeIngestionCommandRequest({ request, projectKey, command });
}

async function readJsonBody(
  request: NextRequest
): Promise<{ ok: true; value: unknown } | { ok: false; error: string }> {
  try {
    return { ok: true, value: await request.json() };
  } catch {
    return { ok: false, error: "Request body must be valid JSON." };
  }
}

function parseCommandRequest(
  value: unknown
):
  | {
      ok: true;
      projectId?: string | number;
      projectKey?: string;
      command: IngestionCommandKind;
      scope: CommandScope;
      claimedActorId?: string;
      reason?: string;
    }
  | { ok: false; error: string } {
  if (!isRecord(value)) {
    return { ok: false, error: "Request body must be a JSON object." };
  }

  const command = readCommand(value.command);
  if (!command) {
    return { ok: false, error: "command must be one of start, pause, shutdown, reset." };
  }

  const scope = readScope(value.scope);
  if (!scope) {
    return {
      ok: false,
      error: "scope must be cluster, target with targetId, task with taskId, or worker with workerId."
    };
  }

  const projectId = readStringOrNumber(value.projectId);
  const projectKey = readOptionalString(value.projectKey);
  const claimedActorId = readOptionalString(value.actorId);
  const reason = readOptionalString(value.reason);

  if (value.projectId !== undefined && projectId === undefined) {
    return { ok: false, error: "projectId must be a string or number." };
  }

  return {
    ok: true,
    ...(projectId !== undefined ? { projectId } : {}),
    ...(projectKey ? { projectKey } : {}),
    command,
    scope,
    ...(claimedActorId ? { claimedActorId } : {}),
    ...(reason ? { reason } : {})
  };
}

function readCommand(value: unknown): IngestionCommandKind | undefined {
  return typeof value === "string" && commandKinds.has(value)
    ? (value as IngestionCommandKind)
    : undefined;
}

function readScope(value: unknown): CommandScope | undefined {
  if (!isRecord(value)) {
    return undefined;
  }

  if (value.type === "cluster") {
    return { type: "cluster" };
  }

  if (value.type === "target") {
    const targetId = readOptionalString(value.targetId);
    return targetId ? { type: "target", targetId } : undefined;
  }

  if (value.type === "task") {
    const taskId = readOptionalString(value.taskId);
    return taskId ? { type: "task", taskId } : undefined;
  }

  if (value.type === "worker") {
    const workerId = readOptionalString(value.workerId);
    return workerId ? { type: "worker", workerId } : undefined;
  }

  return undefined;
}

function readStringOrNumber(value: unknown): string | number | undefined {
  if (
    (typeof value === "string" && value.trim().length > 0) ||
    (typeof value === "number" && Number.isFinite(value))
  ) {
    return value;
  }

  return undefined;
}

function readOptionalString(value: unknown): string | undefined {
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : undefined;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
