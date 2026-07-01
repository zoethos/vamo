import { NextResponse, type NextRequest } from "next/server";
import {
  evaluateProductionInboxPromotion,
  type EvaluateProductionInboxPromotionResult
} from "@confluendo/ingestion-platform/core";
import { loadProgressiveRunSnapshot } from "@confluendo/ingestion-platform/progressive-control-read";
import { recordProductionInboxApproval } from "@confluendo/ingestion-platform/production-inbox-control";
import { authorizeStagingCanaryRequest } from "@/lib/ingestion-admin-auth";

export const runtime = "nodejs";

/**
 * Production-inbox approval endpoint (IP-17).
 *
 * Records the operator decision to allow Confluendo to deliver the reviewed
 * package into Vamo's `confluendo_inbox`. It does not connect to Vamo
 * production and does not apply product rows; the live delivery is a separate,
 * confirmation-gated runbook step, and Vamo applies from the inbox afterward.
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
    snapshot = await loadProgressiveRunSnapshot({ connectionString, projectKey: parsed.projectKey });
  } catch (error) {
    console.error("Production-inbox control read failed", error);
    return NextResponse.json({ ok: false, error: "Failed to read progressive backlog." }, { status: 500 });
  }

  const entry = snapshot?.entries.find(
    (candidate) =>
      candidate.scorecard.targetId === parsed.targetId ||
      candidate.report?.targetId === parsed.targetId
  );
  if (!entry || !entry.report) {
    return NextResponse.json(
      { ok: false, error: "No reviewed run report found for this target." },
      { status: 404 }
    );
  }
  if (!entry.canaryBounds) {
    return NextResponse.json(
      { ok: false, error: "Reviewed bounds are not available for this target." },
      { status: 409 }
    );
  }

  const reportTargetId = entry.report.targetId;
  const decision: EvaluateProductionInboxPromotionResult = evaluateProductionInboxPromotion({
    runReport: entry.report,
    transition: {
      from: "approved_for_production_inbox",
      to: "production_inbox_delivered"
    },
    targetEnvironment: "production",
    stagingCanary: entry.canaryShipment ?? null,
    approval: {
      principal: auth.principal,
      auditReason: parsed.auditReason
    },
    bounds: entry.canaryBounds
  });

  let auditId: string | null = null;
  try {
    const audit = await recordProductionInboxApproval({
      connectionString,
      projectKey: parsed.projectKey,
      targetId: reportTargetId,
      accepted: decision.ok,
      actor: auth.actor,
      reason: parsed.auditReason,
      payload: decision.ok
        ? { plan: decision.plan, principal: auth.auditContext }
        : { blocks: decision.blocks.map((block) => block.code), principal: auth.auditContext }
    });
    auditId = audit.auditId;
  } catch (error) {
    console.error("Production-inbox approval audit failed", error);
    if (decision.ok) {
      return NextResponse.json(
        { ok: false, error: "Production-inbox approval could not be recorded." },
        { status: 500 }
      );
    }
  }

  if (!decision.ok) {
    return NextResponse.json({ ok: false, decision: "blocked", blocks: decision.blocks });
  }
  if (!auditId) {
    return NextResponse.json(
      { ok: false, error: "Production-inbox approval audit id was not returned." },
      { status: 500 }
    );
  }
  return NextResponse.json({ ok: true, decision: "approved", auditId, plan: decision.plan });
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
  | { ok: true; projectKey: string; targetId: string; auditReason: string }
  | { ok: false; error: string } {
  if (!isRecord(value)) {
    return { ok: false, error: "Request body must be a JSON object." };
  }
  const targetId = readString(value.targetId);
  if (!targetId) {
    return { ok: false, error: "targetId is required." };
  }
  const auditReason = readString(value.auditReason);
  if (!auditReason) {
    return { ok: false, error: "A non-empty auditReason is required." };
  }
  return {
    ok: true,
    projectKey: readString(value.projectKey) ?? "vamo",
    targetId,
    auditReason
  };
}

function readString(value: unknown): string | undefined {
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : undefined;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
