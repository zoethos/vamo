import { NextResponse, type NextRequest } from "next/server";
import {
  createSnapshotActivationRequest,
  evaluateSnapshotActivationRequestCreate,
  hasActiveSnapshotActivationRequest,
  loadCommissionedSnapshotPlanContext,
  loadLatestSnapshotCommissionRequest,
  parseSnapshotActivationRequestCreate
} from "@confluendo/ingestion-platform/core";
import { hasFreshAdminStepUp } from "@/lib/autonomy-ramp-step-up";
import { authorizeStagingCanaryRequest } from "@/lib/ingestion-admin-auth";

export const runtime = "nodejs";

/** Records a separately confirmed activation request. It never reads artifacts or activates a release. */
export async function POST(request: NextRequest) {
  const body = await readJsonBody(request);
  if (!body.ok) return NextResponse.json({ ok: false, error: body.error }, { status: 400 });

  const parsed = parseSnapshotActivationRequestCreate(body.value);
  if (!parsed.ok) {
    return NextResponse.json({ ok: false, error: parsed.error, code: parsed.code }, { status: 400 });
  }
  const auth = await authorizeStagingCanaryRequest({ request, projectKey: parsed.request.projectKey });
  if (!auth.ok) return NextResponse.json(auth.body, { status: auth.status });

  const connectionString = process.env.INGESTION_CONTROL_DATABASE_URL?.trim();
  if (!connectionString) {
    return NextResponse.json({ ok: false, error: "Ingestion control database URL is not configured." }, { status: 503 });
  }
  const plan = await loadCommissionedSnapshotPlanContext({
    connectionString,
    projectKey: parsed.request.projectKey
  });
  if (!plan.ok) {
    return NextResponse.json({ ok: false, error: "The commissioned batch plan is unavailable." }, { status: 409 });
  }
  const [commission, hasActiveRequest] = await Promise.all([
    loadLatestSnapshotCommissionRequest({
      connectionString,
      projectKey: parsed.request.projectKey,
      planKey: plan.context.planKey
    }),
    hasActiveSnapshotActivationRequest({
      connectionString,
      projectKey: parsed.request.projectKey,
      planKey: plan.context.planKey
    })
  ]);
  const activationReady =
    commission?.status === "activation_pending" && Boolean(commission.registeredReleaseId);
  const decision = evaluateSnapshotActivationRequestCreate({
    actor: {
      type: "operator",
      id: auth.actor.id,
      role: auth.principal.role,
      assuranceLevel: auth.principal.assuranceLevel,
      stepUpFresh: hasFreshAdminStepUp(auth.principal)
    },
    auditReason: parsed.request.auditReason,
    activationReady,
    hasActiveRequest
  });
  if (!decision.ok) {
    return NextResponse.json({ ok: false, decision: "blocked", blocks: decision.blocks }, { status: 409 });
  }
  if (!commission?.registeredReleaseId) {
    return NextResponse.json({ ok: false, error: "No registered release is ready for activation." }, { status: 409 });
  }

  try {
    const created = await createSnapshotActivationRequest({
      connectionString,
      projectKey: plan.context.projectKey,
      planKey: plan.context.planKey,
      commissionRequestId: commission.requestId,
      releaseId: commission.registeredReleaseId,
      actor: auth.actor,
      auditReason: decision.auditReason
    });
    return NextResponse.json({
      ok: true,
      requestId: created.requestId,
      auditId: created.auditId,
      releaseId: created.releaseId,
      status: created.status
    });
  } catch (error) {
    console.error("Snapshot activation request failed", error);
    const message = error instanceof Error ? error.message : "";
    if (/activation_request_already_active/i.test(message)) {
      return NextResponse.json({ ok: false, error: "An activation request is already active for this batch plan." }, { status: 409 });
    }
    return NextResponse.json({ ok: false, error: "Snapshot activation request could not be recorded." }, { status: 500 });
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
