import { NextResponse, type NextRequest } from "next/server";
import {
  evaluateBatchQueueScheduleDryRun,
  type EvaluateBatchQueueScheduleDryRunResult
} from "@confluendo/ingestion-platform/core";
import { loadBatchQueueSnapshot } from "@confluendo/ingestion-platform/batch-queue-control-read";
import { scheduleBatchDryRun } from "@confluendo/ingestion-platform/batch-queue-mutations";
import { authorizeStagingCanaryRequest } from "@/lib/ingestion-admin-auth";

export const runtime = "nodejs";

/**
 * Batch-queue dry-run scheduling endpoint (IP-18.3).
 *
 * Advances persisted Confluendo control-plane queue rows from ready_for_dry_run
 * to dry_run_ready. It does not execute ingestion, call providers, or write to
 * Vamo staging/production target databases.
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

  const decision: EvaluateBatchQueueScheduleDryRunResult = evaluateBatchQueueScheduleDryRun({
    projectKey: parsed.projectKey,
    snapshot,
    principal: auth.principal,
    auditReason: parsed.auditReason
  });

  if (!decision.ok) {
    return NextResponse.json({ ok: false, decision: "blocked", blocks: decision.blocks }, { status: 409 });
  }

  try {
    const scheduled = await scheduleBatchDryRun({
      connectionString,
      projectKey: parsed.projectKey,
      planId: snapshot.planId,
      targetKey: snapshot.targetKey,
      actor: auth.actor,
      reason: decision.plan.auditReason,
      payload: {
        plan: decision.plan,
        principal: auth.auditContext
      }
    });

    return NextResponse.json({
      ok: true,
      decision: "scheduled",
      plan: decision.plan,
      auditId: scheduled.auditId,
      scheduledCount: scheduled.scheduledCount,
      alreadyScheduledCount: scheduled.alreadyScheduledCount,
      unitKeys: scheduled.unitKeys
    });
  } catch (error) {
    console.error("Batch queue scheduling failed", error);
    return NextResponse.json(
      { ok: false, error: "Batch queue scheduling could not be recorded." },
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
  | { ok: true; projectKey: string; targetKey: string; auditReason: string }
  | { ok: false; error: string } {
  if (!isRecord(value)) {
    return { ok: false, error: "Request body must be a JSON object." };
  }
  const targetKey = readString(value.targetKey);
  if (!targetKey) {
    return { ok: false, error: "targetKey is required." };
  }
  const auditReason = readString(value.auditReason);
  if (!auditReason) {
    return { ok: false, error: "A non-empty auditReason is required." };
  }
  return {
    ok: true,
    projectKey: readString(value.projectKey) ?? "vamo",
    targetKey,
    auditReason
  };
}

function readString(value: unknown): string | undefined {
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : undefined;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
