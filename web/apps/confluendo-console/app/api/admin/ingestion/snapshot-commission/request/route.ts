import { NextResponse, type NextRequest } from "next/server";
import {
  assertCommissionPlanIsCommissionable,
  createSnapshotCommissionRequest,
  evaluateSnapshotCommissionRequestCreate,
  hasActiveSnapshotCommissionRequest,
  loadSnapshotCommissionPlanContext,
  parseSnapshotCommissionRequestCreate,
  presentSnapshotCommissionCard,
  snapshotCommissionOperatorErrorForCode,
  toSnapshotCommissionRequestSummary,
  validateSnapshotCommissionScopeAgainstPlan,
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

  const planContext = await loadSnapshotCommissionPlanContext({
    connectionString,
    projectKey: parsed.request.projectKey,
    planKey: parsed.request.planKey
  });
  if (!planContext) {
    return NextResponse.json(
      {
        ok: false,
        code: "plan_not_found",
        error: snapshotCommissionOperatorErrorForCode("plan_not_found")
      },
      { status: 404 }
    );
  }

  const planEligibility = assertCommissionPlanIsCommissionable(planContext);
  if (!planEligibility.ok) {
    return NextResponse.json(
      { ok: false, code: planEligibility.code, error: planEligibility.error },
      { status: 409 }
    );
  }

  const scopeDecision = validateSnapshotCommissionScopeAgainstPlan({
    countries: parsed.request.countries,
    categories: parsed.request.categories,
    maxRowsPerScope: parsed.request.maxRowsPerScope ?? 250,
    plan: planContext
  });
  if (!scopeDecision.ok) {
    return NextResponse.json(
      { ok: false, code: scopeDecision.code, error: scopeDecision.error },
      { status: 400 }
    );
  }

  const hasActiveRequest = await hasActiveSnapshotCommissionRequest({
    connectionString,
    projectKey: parsed.request.projectKey,
    planKey: planContext.planKey
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
      projectKey: planContext.projectKey,
      planKey: planContext.planKey,
      countries: scopeDecision.countries,
      categories: scopeDecision.categories,
      maxRowsPerScope: scopeDecision.maxRowsPerScope,
      actor: auth.actor,
      auditReason: decision.auditReason
    });

    const requestRecord: SnapshotCommissionRequestRecord = {
      requestId: created.requestId,
      projectKey: planContext.projectKey,
      planKey: planContext.planKey,
      sourceKey: created.sourceKey,
      status: created.status,
      countries: [...scopeDecision.countries],
      categories: [...scopeDecision.categories],
      maxRowsPerScope: scopeDecision.maxRowsPerScope,
      auditReason: decision.auditReason,
      requestedByType: auth.actor.type,
      requestedById: auth.actor.id,
      requestedAt: new Date().toISOString()
    };

    const card = presentSnapshotCommissionCard({
      request: requestRecord,
      hasActiveRequest: true,
      defaultSourceKey: planContext.sourceKey,
      defaultCountries: planContext.allowedCountries,
      defaultCategories: planContext.allowedCategories,
      defaultMaxRowsPerScope: planContext.maxRowsPerScopeLimit
    });

    return NextResponse.json({
      ok: true,
      requestId: created.requestId,
      auditId: created.auditId,
      status: created.status,
      sourceKey: created.sourceKey,
      card,
      request: toSnapshotCommissionRequestSummary(requestRecord)
    });
  } catch (error) {
    console.error("Snapshot commission request failed", error);
    const message =
      error instanceof Error ? error.message : "Snapshot commission request could not be recorded.";
    if (/commission_request_already_active/i.test(message)) {
      return NextResponse.json(
        {
          ok: false,
          code: "commission_request_already_active",
          error: snapshotCommissionOperatorErrorForCode("commission_request_already_active")
        },
        { status: 409 }
      );
    }
    if (/plan_not_active/i.test(message)) {
      return NextResponse.json(
        {
          ok: false,
          code: "plan_not_active",
          error: snapshotCommissionOperatorErrorForCode("plan_not_active")
        },
        { status: 409 }
      );
    }
    if (/unsupported_source_key/i.test(message)) {
      return NextResponse.json(
        {
          ok: false,
          code: "unsupported_source_key",
          error: snapshotCommissionOperatorErrorForCode("unsupported_source_key")
        },
        { status: 409 }
      );
    }
    return NextResponse.json(
      { ok: false, error: "Snapshot commission request could not be recorded." },
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
