import { NextResponse, type NextRequest } from "next/server";
import {
  evaluateBatchPlanContractRefresh,
  loadBatchPlanSourceTaxonomyState,
  loadCommissionedSnapshotPlanContext,
  parseBatchPlanContractRefreshRequest,
  refreshBatchPlanSourceTaxonomy,
  resolvePublishedPlanSourceTaxonomyContract
} from "@confluendo/ingestion-platform/core";
import { hasFreshAdminStepUp } from "@/lib/autonomy-ramp-step-up";
import { authorizeStagingCanaryRequest } from "@/lib/ingestion-admin-auth";
import { getActiveControlEnvironmentConfig } from "@/lib/control-environment-server";

export const runtime = "nodejs";

/**
 * Writes only a server-pinned published source taxonomy through the protected
 * control-plane function. It never accepts plan or taxonomy content from the
 * browser and never reseeds queue state.
 */
export async function POST(request: NextRequest) {
  const body = await readJsonBody(request);
  if (!body.ok) {
    return NextResponse.json({ ok: false, error: body.error }, { status: 400 });
  }

  const parsed = parseBatchPlanContractRefreshRequest(body.value);
  if (!parsed.ok) {
    return NextResponse.json(
      { ok: false, code: parsed.code, error: parsed.error },
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

  const commissionedPlan = await loadCommissionedSnapshotPlanContext({
    connectionString,
    projectKey: parsed.request.projectKey
  });
  if (!commissionedPlan.ok) {
    return NextResponse.json(
      {
        ok: false,
        code: commissionedPlan.code,
        error: "The active plan context could not be resolved for contract refresh."
      },
      { status: commissionedPlan.code === "plan_not_found" ? 404 : 409 }
    );
  }

  const plan = commissionedPlan.context;
  const currentPlan = await loadBatchPlanSourceTaxonomyState({
    connectionString,
    projectKey: plan.projectKey,
    planKey: plan.planKey
  });
  if (!currentPlan || currentPlan.sourceKey !== plan.sourceKey || currentPlan.status !== "active") {
    return NextResponse.json(
      { ok: false, error: "The active plan changed. Refresh the console before retrying." },
      { status: 409 }
    );
  }
  const publishedContract = resolvePublishedPlanSourceTaxonomyContract({
    projectKey: plan.projectKey,
    planKey: plan.planKey,
    sourceKey: plan.sourceKey
  });
  const decision = evaluateBatchPlanContractRefresh({
    actor: {
      type: "operator",
      id: auth.actor.id,
      role: auth.principal.role,
      assuranceLevel: auth.principal.assuranceLevel,
      stepUpFresh: hasFreshAdminStepUp(auth.principal)
    },
    auditReason: parsed.request.auditReason,
    currentSourceTaxonomy: currentPlan.sourceTaxonomy,
    publishedContract
  });
  if (!decision.ok) {
    return NextResponse.json({ ok: false, decision: "blocked", blocks: decision.blocks }, { status: 409 });
  }

  try {
    const result = await refreshBatchPlanSourceTaxonomy({
      connectionString,
      projectKey: plan.projectKey,
      planKey: plan.planKey,
      sourceKey: plan.sourceKey,
      sourceTaxonomy: decision.sourceTaxonomy,
      actor: auth.actor,
      auditReason: decision.auditReason
    });
    return NextResponse.json({
      ok: true,
      changed: result.changed,
      planKey: result.planKey,
      sourceKey: result.sourceKey,
      auditId: result.auditId
    });
  } catch (error) {
    console.error("Batch plan source-taxonomy refresh failed", error);
    const message = error instanceof Error ? error.message : "";
    const conflict = /plan_not_active|plan_source_mismatch/i.test(message);
    return NextResponse.json(
      {
        ok: false,
        error: conflict
          ? "The active plan changed. Refresh the console before retrying."
          : "The plan contract refresh could not be recorded."
      },
      { status: conflict ? 409 : 500 }
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
