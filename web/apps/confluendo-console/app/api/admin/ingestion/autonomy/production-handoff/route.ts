import { NextResponse, type NextRequest } from "next/server";
import { Client } from "pg";
import {
  evaluateAutonomyProductionHandoffChange,
  parseAutonomyProductionHandoffRequest,
  presentAutonomyProductionHandoffCard,
  setAutonomyProductionHandoff
} from "@confluendo/ingestion-platform/core";
import { loadAutonomyPolicy } from "@confluendo/ingestion-platform/autonomy-control-read";
import { hasFreshAdminStepUp } from "@/lib/autonomy-ramp-step-up";
import { authorizeStagingCanaryRequest } from "@/lib/ingestion-admin-auth";
import { getActiveControlEnvironmentConfig } from "@/lib/control-environment-server";

export const runtime = "nodejs";

/**
 * Production package autonomy handoff endpoint (IP-18.8.7).
 *
 * Control-plane only: calls setAutonomyProductionHandoff(...). No provider calls,
 * no staging writes, no production inbox delivery, and no consumer apply.
 */
export async function POST(request: NextRequest) {
  const body = await readJsonBody(request);
  if (!body.ok) {
    return NextResponse.json({ ok: false, error: body.error }, { status: 400 });
  }

  const parsed = parseAutonomyProductionHandoffRequest(body.value);
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
  const client = new Client({ connectionString });
  try {
    await client.connect();
    policy = await loadAutonomyPolicy(client, {
      projectKey: parsed.request.projectKey,
      policyKey: parsed.request.policyKey
    });
  } catch (error) {
    console.error("Production handoff policy read failed", error);
    return NextResponse.json(
      { ok: false, error: "Failed to read production handoff policy context." },
      { status: 500 }
    );
  } finally {
    await client.end();
  }

  if (!policy) {
    return NextResponse.json(
      { ok: false, error: "No active autonomy policy was found for this project and policy key." },
      { status: 404 }
    );
  }

  const card = presentAutonomyProductionHandoffCard(policy);
  if (parsed.request.expectedEnabled !== card.enabled) {
    return NextResponse.json(
      {
        ok: false,
        decision: "blocked",
        blocks: [
          {
            code: "production_handoff_conflict",
            message: `Production handoff is now ${card.stateLabel.toLowerCase()}; refresh before changing it.`
          }
        ]
      },
      { status: 409 }
    );
  }

  const decision = evaluateAutonomyProductionHandoffChange({
    currentEnabled: card.enabled,
    requestedEnabled: parsed.request.requestedEnabled,
    actor: {
      type: "operator",
      id: auth.actor.id,
      role: auth.principal.role,
      assuranceLevel: auth.principal.assuranceLevel,
      stepUpFresh: hasFreshAdminStepUp(auth.principal)
    },
    auditReason: parsed.request.auditReason
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
    const result = await setAutonomyProductionHandoff({
      connectionString,
      projectKey: parsed.request.projectKey,
      policyKey: parsed.request.policyKey,
      expectedEnabled: parsed.request.expectedEnabled,
      requestedEnabled: parsed.request.requestedEnabled,
      actor: auth.actor,
      auditReason: decision.auditReason
    });

    return NextResponse.json({
      ok: true,
      decision: decision.direction,
      fromEnabled: result.fromEnabled,
      toEnabled: result.toEnabled,
      policyVersion: result.policyVersion,
      auditId: result.auditId,
      productionInboxHandoffPolicy: result.productionInboxHandoffPolicy,
      allowedTransitions: result.allowedTransitions
    });
  } catch (error) {
    console.error("Production handoff change failed", error);
    const message =
      error instanceof Error
        ? error.message
        : "Production handoff policy change could not be recorded.";
    const status = /production_handoff_conflict|same_production_handoff_state/i.test(message)
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
