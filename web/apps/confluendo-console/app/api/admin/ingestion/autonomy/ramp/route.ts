import { NextResponse, type NextRequest } from "next/server";
import { Client } from "pg";
import {
  AUTONOMY_RAMP_MODES,
  evaluateAutonomyRampPromotion,
  loadAutonomyRampReadiness,
  parseAutonomyRampPromoteRequest,
  presentAutonomyRampCard,
  promoteAutonomyRamp
} from "@confluendo/ingestion-platform/core";
import { loadAutonomyPolicy } from "@confluendo/ingestion-platform/autonomy-control-read";
import { loadBatchQueueSnapshot } from "@confluendo/ingestion-platform/batch-queue-control-read";
import { authorizeStagingCanaryRequest } from "@/lib/ingestion-admin-auth";
import { getActiveControlEnvironmentConfig } from "@/lib/control-environment-server";
import { hasFreshAdminStepUp } from "@/lib/autonomy-ramp-step-up";

export const runtime = "nodejs";

/**
 * Autonomy ramp promotion/demotion endpoint (IP-18.7.4 PR2).
 *
 * Control-plane only: calls promoteAutonomyRamp(...) — no provider calls, no staging
 * writes, no production inbox delivery, no consumer apply.
 */
export async function POST(request: NextRequest) {
  const body = await readJsonBody(request);
  if (!body.ok) {
    return NextResponse.json({ ok: false, error: body.error }, { status: 400 });
  }

  const parsed = parseAutonomyRampPromoteRequest(body.value);
  if (!parsed.ok) {
    return NextResponse.json(
      { ok: false, error: parsed.error, code: parsed.code },
      { status: 400 }
    );
  }

  const auth = await authorizeStagingCanaryRequest({
    request,
    projectKey: parsed.request.projectKey
  });
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

  let policy;
  let queueSnapshot;
  let readiness;
  const client = new Client({ connectionString });
  try {
    await client.connect();
    [policy, queueSnapshot, readiness] = await Promise.all([
      loadAutonomyPolicy(client, {
        projectKey: parsed.request.projectKey,
        policyKey: parsed.request.policyKey
      }),
      loadBatchQueueSnapshot({
        connectionString,
        projectKey: parsed.request.projectKey
      }),
      loadAutonomyRampReadiness({
        connectionString,
        projectKey: parsed.request.projectKey,
        policyKey: parsed.request.policyKey
      })
    ]);
  } catch (error) {
    console.error("Autonomy ramp context read failed", error);
    return NextResponse.json({ ok: false, error: "Failed to read autonomy ramp context." }, { status: 500 });
  } finally {
    await client.end();
  }

  if (!policy) {
    return NextResponse.json(
      { ok: false, error: "No active autonomy policy was found for this project and policy key." },
      { status: 404 }
    );
  }

  const blockerSummaries = queueSnapshot?.blockerSummaries ?? [];
  const blockedUnitCount = queueSnapshot?.progress.blocked ?? 0;
  const presentation = presentAutonomyRampCard({
    policy,
    readiness,
    blockerSummaries,
    blockedUnitCount
  });
  const currentMode = presentation.currentMode;

  if (parsed.request.expectedCurrentMode !== currentMode) {
    return NextResponse.json(
      {
        ok: false,
        decision: "blocked",
        blocks: [
          {
            code: "ramp_mode_conflict",
            message: `Current ramp mode is ${currentMode}; refresh before changing it.`
          }
        ]
      },
      { status: 409 }
    );
  }

  const currentIndex = AUTONOMY_RAMP_MODES.indexOf(currentMode);
  const requestedIndex = AUTONOMY_RAMP_MODES.indexOf(parsed.request.requestedMode);
  const direction =
    currentIndex >= 0 && requestedIndex >= 0 && requestedIndex < currentIndex ? "demotion" : "promotion";

  if (
    direction === "promotion" &&
    presentation.advisoryWarnings.length > 0 &&
    parsed.request.acknowledgedWarnings !== true
  ) {
    return NextResponse.json(
      {
        ok: false,
        decision: "blocked",
        blocks: [
          {
            code: "advisory_warnings_unacknowledged",
            message: "Acknowledge advisory warnings before promoting."
          }
        ],
        warnings: presentation.advisoryWarnings
      },
      { status: 409 }
    );
  }

  const decision = evaluateAutonomyRampPromotion({
    currentMode,
    requestedMode: parsed.request.requestedMode,
    actor: {
      type: "operator",
      id: auth.actor.id,
      role: auth.principal.role,
      assuranceLevel: auth.principal.assuranceLevel,
      stepUpFresh: hasFreshAdminStepUp(auth.principal)
    },
    auditReason: parsed.request.auditReason,
    blockerSummaries,
    blockedUnitCount
  });

  if (!decision.ok) {
    return NextResponse.json(
      {
        ok: false,
        decision: "blocked",
        blocks: decision.blocks
      },
      { status: 409 }
    );
  }

  try {
    const result = await promoteAutonomyRamp({
      connectionString,
      projectKey: parsed.request.projectKey,
      policyKey: parsed.request.policyKey,
      expectedCurrentMode: currentMode,
      requestedMode: parsed.request.requestedMode,
      actor: auth.actor,
      auditReason: parsed.request.auditReason
    });

    return NextResponse.json({
      ok: true,
      decision: decision.direction,
      fromMode: result.fromMode,
      toMode: result.toMode,
      auditId: result.auditId,
      policyId: result.policyId
    });
  } catch (error) {
    console.error("Autonomy ramp promotion failed", error);
    const message = error instanceof Error ? error.message : "Autonomy ramp change could not be recorded.";
    const status = /ramp_mode_conflict|same_mode|skips_required_ramp|steady_state_locked/i.test(message)
      ? 409
      : 500;
    return NextResponse.json({ ok: false, error: message }, { status });
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
