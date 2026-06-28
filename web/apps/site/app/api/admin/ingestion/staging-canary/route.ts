import { NextResponse, type NextRequest } from "next/server";
import {
  evaluateStagingCanaryPromotion,
  type EvaluateStagingCanaryPromotionResult
} from "@vamo/ingestion-platform/core";
import { loadProgressiveRunSnapshot } from "@vamo/ingestion-platform/progressive-control-read";
import { recordStagingCanaryApproval } from "@vamo/ingestion-platform/staging-canary-control";
import { authorizeStagingCanaryRequest } from "@/lib/ingestion-admin-auth";

export const runtime = "nodejs";

/**
 * Staging-canary approval decision endpoint (IP-16, Phase 4).
 *
 * Enforces the operator gate (authenticated ingestion_admin + AAL2 + fresh
 * step-up + non-empty audit reason via the pure policy), evaluates the
 * `review_required -> staging_write` promotion against the reviewed run report
 * from the control plane, and records the decision in the audit log.
 *
 * It does NOT perform a target write. The live staging canary is a separate,
 * confirmation-gated runbook/CLI step. The browser never receives DB
 * credentials; everything here is server-side.
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
    console.error("Staging-canary control read failed", error);
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

  // Normalize the audit/target identity to the reviewed run report so the
  // dashboard approval, the recorded plan, and the live CLI all key off the
  // same targetId (the lookup above accepts either the scorecard or report id).
  const reportTargetId = entry.report.targetId;
  const reviewedBounds = entry.canaryBounds;
  if (!reviewedBounds) {
    return NextResponse.json(
      { ok: false, error: "Reviewed canary bounds are not available for this target." },
      { status: 409 }
    );
  }

  const decision: EvaluateStagingCanaryPromotionResult = evaluateStagingCanaryPromotion({
    runReport: entry.report,
    transition: { from: "review_required", to: "staging_write" },
    // The dashboard approval promotes specifically to staging; the live CLI
    // independently proves the connection is staging before any write.
    targetEnvironment: "staging",
    approval: {
      principal: auth.principal,
      auditReason: parsed.auditReason
    },
    // Bounds are derived from the reviewed proposal/run report in the control
    // plane. Browser-supplied geography/category/maxRows are intentionally not
    // trusted because they can loosen the approved canary scope.
    bounds: reviewedBounds
  });

  let auditId: string | null = null;
  // Record the decision (accepted or blocked) for forensics. Accepted
  // approvals are authoritative only once the audit row exists; otherwise the
  // live CLI has nothing durable to bind to.
  try {
    const audit = await recordStagingCanaryApproval({
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
    console.error("Staging-canary approval audit failed", error);
    if (decision.ok) {
      return NextResponse.json(
        { ok: false, error: "Staging-canary approval could not be recorded." },
        { status: 500 }
      );
    }
  }

  if (!decision.ok) {
    return NextResponse.json({ ok: false, decision: "blocked", blocks: decision.blocks });
  }

  if (!auditId) {
    return NextResponse.json(
      { ok: false, error: "Staging-canary approval audit id was not returned." },
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
