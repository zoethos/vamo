import { NextResponse, type NextRequest } from "next/server";
import {
  evaluateBatchStagingCanaryWaveApproval,
  approveBatchStagingCanaryWave,
  parseBatchStagingCanaryWaveApproveRequest,
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
  const parsed = parseBatchStagingCanaryWaveApproveRequest(body.value);
  if (!parsed.ok) {
    return NextResponse.json({ ok: false, error: parsed.error }, { status: 400 });
  }

  const auth = await authorizeStagingCanaryRequest({
    request,
    projectKey: parsed.request.projectKey
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
      projectKey: parsed.request.projectKey,
      targetKey: parsed.request.targetKey
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
      projectKey: parsed.request.projectKey,
      snapshot,
      principal: auth.principal,
      targetKey: parsed.request.targetKey,
      targetEnvironment: parsed.request.targetEnvironment,
      maxUnits: parsed.request.maxUnits,
      maxRows: parsed.request.maxRows,
      auditReason: parsed.request.auditReason,
      unitKeys: parsed.request.unitKeys
    });

  if (!decision.ok) {
    return NextResponse.json(
      {
        ok: false,
        decision: "blocked",
        blocks: decision.blocks,
        unitIssues: decision.unitIssues
      },
      { status: 409 }
    );
  }

  try {
    const approved = await approveBatchStagingCanaryWave({
      connectionString,
      projectKey: parsed.request.projectKey,
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
