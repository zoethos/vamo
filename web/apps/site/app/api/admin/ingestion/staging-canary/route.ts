import { NextResponse, type NextRequest } from "next/server";
import {
  evaluateStagingCanaryPromotion,
  type EvaluateStagingCanaryPromotionResult,
  type StagingCanaryBounds
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
    bounds: parsed.bounds
  });

  // Record the decision (accepted or blocked) for forensics. Never fatal to the
  // response: a missing project or audit failure should not hide the decision.
  try {
    await recordStagingCanaryApproval({
      connectionString,
      projectKey: parsed.projectKey,
      targetId: parsed.targetId,
      accepted: decision.ok,
      actor: auth.actor,
      reason: parsed.auditReason,
      payload: decision.ok
        ? { plan: decision.plan, principal: auth.auditContext }
        : { blocks: decision.blocks.map((block) => block.code), principal: auth.auditContext }
    });
  } catch (error) {
    console.error("Staging-canary approval audit failed", error);
  }

  if (!decision.ok) {
    return NextResponse.json({ ok: false, decision: "blocked", blocks: decision.blocks });
  }

  return NextResponse.json({ ok: true, decision: "approved", plan: decision.plan });
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
  | { ok: true; projectKey: string; targetId: string; auditReason: string; bounds: StagingCanaryBounds }
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

  const boundsValue = isRecord(value.bounds) ? value.bounds : undefined;
  const geography = boundsValue ? readString(boundsValue.geography) : undefined;
  const category = boundsValue ? readString(boundsValue.category) : undefined;
  if (!geography || !category) {
    return { ok: false, error: "bounds.geography and bounds.category are required." };
  }

  const maxRows = boundsValue ? readPositiveInt(boundsValue.maxRows) : undefined;

  return {
    ok: true,
    projectKey: readString(value.projectKey) ?? "vamo",
    targetId,
    auditReason,
    bounds: { geography, category, ...(maxRows !== undefined ? { maxRows } : {}) }
  };
}

function readString(value: unknown): string | undefined {
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : undefined;
}

function readPositiveInt(value: unknown): number | undefined {
  return typeof value === "number" && Number.isInteger(value) && value > 0 ? value : undefined;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
