import { NextResponse, type NextRequest } from "next/server";
import {
  createSnapshotCommissionRequest,
  evaluateSnapshotCommissionRequestCreate,
  hasActiveSnapshotCommissionRequest,
  parseSnapshotCommissionRequestCreate,
  presentSnapshotCommissionCard,
  toSnapshotCommissionRequestSummary,
  type SnapshotCommissionRequestRecord
} from "@confluendo/ingestion-platform/core";
import { hasFreshAdminStepUp } from "@/lib/autonomy-ramp-step-up";
import { authorizeStagingCanaryRequest } from "@/lib/ingestion-admin-auth";

export const runtime = "nodejs";

/**
 * Snapshot release commissioning request endpoint (IP-18.8.13).
 *
 * Control-plane only: records a commissioning request for a trusted worker.
 * No provider calls, artifact access, activation, staging, production, or apply.
 */
export async function POST(request: NextRequest) {
  const body = await readJsonBody(request);
  if (!body.ok) {
    return NextResponse.json({ ok: false, error: body.error }, { status: 400 });
  }

  const parsed = parseSnapshotCommissionRequestCreate(body.value);
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

  const connectionString = process.env.INGESTION_CONTROL_DATABASE_URL?.trim();
  if (!connectionString) {
    return NextResponse.json(
      { ok: false, error: "Ingestion control database URL is not configured." },
      { status: 503 }
    );
  }

  const hasActiveRequest = await hasActiveSnapshotCommissionRequest({
    connectionString,
    projectKey: parsed.request.projectKey,
    planKey: parsed.request.planKey
  });

  const decision = evaluateSnapshotCommissionRequestCreate({
    actor: {
      type: "operator",
      id: auth.actor.id,
      role: auth.principal.role,
      assuranceLevel: auth.principal.assuranceLevel,
      stepUpFresh: hasFreshAdminStepUp(auth.principal)
    },
    auditReason: parsed.request.auditReason,
    hasActiveRequest
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
    const created = await createSnapshotCommissionRequest({
      connectionString,
      projectKey: parsed.request.projectKey,
      planKey: parsed.request.planKey,
      sourceKey: parsed.request.sourceKey,
      countries: parsed.request.countries,
      categories: parsed.request.categories,
      maxRowsPerScope: parsed.request.maxRowsPerScope ?? 250,
      actor: auth.actor,
      auditReason: decision.auditReason
    });

    const requestRecord: SnapshotCommissionRequestRecord = {
      requestId: created.requestId,
      projectKey: parsed.request.projectKey,
      planKey: parsed.request.planKey,
      sourceKey: parsed.request.sourceKey,
      status: created.status,
      countries: [...parsed.request.countries],
      categories: [...parsed.request.categories],
      maxRowsPerScope: parsed.request.maxRowsPerScope ?? 250,
      auditReason: decision.auditReason,
      requestedByType: auth.actor.type,
      requestedById: auth.actor.id,
      requestedAt: new Date().toISOString()
    };

    const card = presentSnapshotCommissionCard({
      request: requestRecord,
      hasActiveRequest: true,
      defaultSourceKey: parsed.request.sourceKey,
      defaultCountries: [...parsed.request.countries],
      defaultCategories: [...parsed.request.categories],
      defaultMaxRowsPerScope: parsed.request.maxRowsPerScope ?? 250
    });

    return NextResponse.json({
      ok: true,
      requestId: created.requestId,
      auditId: created.auditId,
      status: created.status,
      card,
      request: toSnapshotCommissionRequestSummary(requestRecord)
    });
  } catch (error) {
    console.error("Snapshot commission request failed", error);
    const message =
      error instanceof Error ? error.message : "Snapshot commission request could not be recorded.";
    const status = /commission_request_already_active/i.test(message) ? 409 : 500;
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
