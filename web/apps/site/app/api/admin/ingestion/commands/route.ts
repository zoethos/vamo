import { NextResponse, type NextRequest } from "next/server";
import {
  applyPostgresIngestionCommand,
  type CommandScope,
  type IngestionCommandKind
} from "@vamo/ingestion-platform/control-api";

export const runtime = "nodejs";

const commandKinds = new Set(["start", "pause", "shutdown", "reset"]);

export async function POST(request: NextRequest) {
  const adminToken = process.env.INGESTION_ADMIN_API_TOKEN?.trim();
  if (!adminToken) {
    return NextResponse.json(
      { ok: false, error: "Ingestion admin API token is not configured." },
      { status: 503 }
    );
  }

  if (request.headers.get("authorization") !== `Bearer ${adminToken}`) {
    return NextResponse.json({ ok: false, error: "Unauthorized." }, { status: 401 });
  }

  const connectionString = process.env.INGESTION_CONTROL_DATABASE_URL?.trim();
  if (!connectionString) {
    return NextResponse.json(
      { ok: false, error: "Ingestion control database URL is not configured." },
      { status: 503 }
    );
  }

  const body = await readJsonBody(request);
  if (!body.ok) {
    return NextResponse.json({ ok: false, error: body.error }, { status: 400 });
  }

  const parsed = parseCommandRequest(body.value);
  if (!parsed.ok) {
    return NextResponse.json({ ok: false, error: parsed.error }, { status: 400 });
  }

  const result = await applyCommand({
    connectionString,
    projectId: parsed.projectId,
    projectKey: parsed.projectKey ?? "vamo",
    command: parsed.command,
    scope: parsed.scope,
    actorId: parsed.actorId,
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
  actorId?: string;
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
        actor: {
          type: "operator",
          id: input.actorId ?? "admin-api"
        },
        reason: input.reason
      })
    };
  } catch (error) {
    return {
      ok: false,
      status: error instanceof Error && error.message.includes("project was not found") ? 404 : 500,
      body: {
        ok: false,
        error: error instanceof Error ? error.message : "Ingestion command failed."
      }
    };
  }
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
      actorId?: string;
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
  const actorId = readOptionalString(value.actorId);
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
    ...(actorId ? { actorId } : {}),
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
