import { NextResponse, type NextRequest } from "next/server";
import {
  evaluateBatchStagingCanaryWaveApproval,
  approveBatchStagingCanaryWave,
  type EvaluateBatchStagingCanaryWaveApprovalResult
} from "@confluendo/ingestion-platform/core";
import { loadBatchQueueSnapshot } from "@confluendo/ingestion-platform/batch-queue-control-read";
import { authorizeStagingCanaryRequest } from "@/lib/ingestion-admin-auth";

export const runtime = "nodejs";

/**
 * Batch staging-canary wave approval endpoint (IP-18.5.1).
 *
 * Requires ingestion_admin (role=admin) + verified AAL2 + fresh MFA step-up +
 * non-empty audit reason via the pure policy. Records the approved wave in the
 * Confluendo control DB only — no Vamo staging write.
 */
export async function POST(request: NextRequest) {
  const body = await readJsonBody(request);
  if (!body.ok) {
    return NextResponse.json({ ok: false, error: body.error }, { status: 400 });
  }
  const parsed = parseRequest(body.value);
  if (!parsed.ok) {
    return NextResponse.json({ ok: false, error: parsed.error }, { status: 400 });
  }

  const auth = await authorizeStagingCanaryRequest({
    request,
    projectKey: parsed.projectKey
  });
  if (!auth.ok) {
    return NextResponse.json(auth.body, { status: auth.status });
  }

  const connectionString = process.env.INGESTION_CONTROL_DATABASE_URL?.trim();
  if (!connectionString) {
    return NextResponse.json(
      { ok: false, error: "Ingestion control database URL is not configured." },
      { status: 503 }
    );
  }

  let snapshot;
  try {
    snapshot = await loadBatchQueueSnapshot({
      connectionString,
      projectKey: parsed.projectKey,
      targetKey: parsed.targetKey
    });
  } catch (error) {
    console.error("Batch queue control read failed", error);
    return NextResponse.json({ ok: false, error: "Failed to read batch queue." }, { status: 500 });
  }

  if (!snapshot) {
    return NextResponse.json(
      { ok: false, error: "No persisted batch queue was found for this project and target." },
      { status: 404 }
    );
  }

  const decision: EvaluateBatchStagingCanaryWaveApprovalResult =
    evaluateBatchStagingCanaryWaveApproval({
      projectKey: parsed.projectKey,
      snapshot,
      principal: auth.principal,
      targetKey: parsed.targetKey,
      targetEnvironment: parsed.targetEnvironment,
      maxUnits: parsed.maxUnits,
      maxRows: parsed.maxRows,
      auditReason: parsed.auditReason
    });

  if (!decision.ok) {
    return NextResponse.json({ ok: false, decision: "blocked", blocks: decision.blocks }, { status: 409 });
  }

  try {
    const approved = await approveBatchStagingCanaryWave({
      connectionString,
      projectKey: parsed.projectKey,
      plan: decision.plan,
      actor: auth.actor
    });

    return NextResponse.json({
      ok: true,
      decision: "approved",
      plan: decision.plan,
      auditId: approved.auditId,
      waveId: approved.waveId,
      waveKey: approved.waveKey,
      unitKeys: approved.unitKeys,
      idempotentReplay: approved.idempotentReplay
    });
  } catch (error) {
    console.error("Batch staging-canary wave approval failed", error);
    return NextResponse.json(
      { ok: false, error: "Batch staging-canary wave approval could not be recorded." },
      { status: 500 }
    );
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

function parseRequest(
  value: unknown
):
  | {
      ok: true;
      projectKey: string;
      targetKey: string;
      targetEnvironment: string;
      maxUnits: number;
      maxRows: number;
      auditReason: string;
    }
  | { ok: false; error: string } {
  if (!isRecord(value)) {
    return { ok: false, error: "Request body must be a JSON object." };
  }
  const targetKey = readString(value.targetKey);
  if (!targetKey) {
    return { ok: false, error: "targetKey is required." };
  }
  const targetEnvironment = readString(value.targetEnvironment) ?? "staging";
  if (targetEnvironment !== "staging") {
    return { ok: false, error: "targetEnvironment must be staging for IP-18.5." };
  }
  const auditReason = readString(value.auditReason);
  if (!auditReason) {
    return { ok: false, error: "A non-empty auditReason is required." };
  }
  const maxUnits = readPositiveInt(value.maxUnits, 1);
  const maxRows = readPositiveInt(value.maxRows, 50);
  if (!maxUnits || !maxRows) {
    return { ok: false, error: "maxUnits and maxRows must be positive integers." };
  }
  return {
    ok: true,
    projectKey: readString(value.projectKey) ?? "vamo",
    targetKey,
    targetEnvironment,
    maxUnits,
    maxRows,
    auditReason
  };
}

function readPositiveInt(value: unknown, fallback: number): number | undefined {
  if (value === undefined || value === null) {
    return fallback;
  }
  if (typeof value !== "number" || !Number.isInteger(value) || value < 1) {
    return undefined;
  }
  return value;
}

function readString(value: unknown): string | undefined {
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : undefined;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
