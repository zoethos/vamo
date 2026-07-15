import { NextResponse, type NextRequest } from "next/server";
import {
  approveBatchProductionPackageWave,
  evaluateProductionPackageWaveApproval,
  loadProductionPackageWaveApprovalContext,
  parseProductionPackageWaveApproveRequest,
  enrichProductionPackageWaveApprovalPlanWithStagedContentHashes,
  loadActiveSnapshotReleasePlanBinding,
  resolveSnapshotCandidateLoader,
  describeProductionPackageContentEquivalence,
  type EvaluateProductionPackageWaveApprovalResult
} from "@confluendo/ingestion-platform/core";
import { loadBatchQueueSnapshot } from "@confluendo/ingestion-platform/batch-queue-control-read";
import { authorizeStagingCanaryRequest } from "@/lib/ingestion-admin-auth";
import { getActiveControlEnvironmentConfig } from "@/lib/control-environment-server";

export const runtime = "nodejs";

/**
 * Production package-wave approval endpoint (IP-18.6.2).
 *
 * Records a control-plane package-wave approval only. No production inbox
 * delivery, no consumer apply, and no Vamo product-table writes.
 */
export async function POST(request: NextRequest) {
  const body = await readJsonBody(request);
  if (!body.ok) {
    return NextResponse.json({ ok: false, error: body.error }, { status: 400 });
  }

  const parsed = parseProductionPackageWaveApproveRequest(body.value);
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

  const environmentConfig = await getActiveControlEnvironmentConfig();
  if (environmentConfig?.environment !== "production") {
    return NextResponse.json(
      { ok: false, error: "Production package approval is available only in the Production workspace." },
      { status: 409 }
    );
  }
  const connectionString = environmentConfig.controlDatabaseUrl;
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

  let approvalContext;
  try {
    approvalContext = await loadProductionPackageWaveApprovalContext({
      connectionString,
      projectKey: parsed.request.projectKey,
      targetKey: parsed.request.targetKey
    });
  } catch (error) {
    console.error("Production package-wave context read failed", error);
    return NextResponse.json(
      { ok: false, error: "Failed to read production package-wave context." },
      { status: 500 }
    );
  }

  const decision: EvaluateProductionPackageWaveApprovalResult =
    evaluateProductionPackageWaveApproval({
      projectKey: parsed.request.projectKey,
      snapshot,
      principal: auth.principal,
      targetKey: parsed.request.targetKey,
      targetEnvironment: parsed.request.targetEnvironment,
      schemaContract: parsed.request.schemaContract,
      maxUnits: parsed.request.maxUnits,
      maxRows: parsed.request.maxRows,
      maxPackages: parsed.request.maxPackages,
      auditReason: parsed.request.auditReason,
      stagingEvidenceByUnitKey: approvalContext.stagingEvidenceByUnitKey,
      occupiedUnitKeys: approvalContext.occupiedUnitKeys,
      hasPriorDeliveredPackage: approvalContext.hasPriorDeliveredPackage,
      unitKeys: parsed.request.unitKeys
    });

  if (!decision.ok) {
    return NextResponse.json(
      { ok: false, decision: "blocked", blocks: decision.blocks, unitIssues: decision.unitIssues },
      { status: 409 }
    );
  }

  let enrichedPlan;
  try {
    const activeRelease = await loadActiveSnapshotReleasePlanBinding({
      connectionString,
      projectKey: parsed.request.projectKey,
      planKey: snapshot.planId
    });
    const loadCandidates = activeRelease
      ? async () => []
      : (
          await resolveSnapshotCandidateLoader({
            controlConnectionString: connectionString,
            projectKey: parsed.request.projectKey,
            planKey: snapshot.planId
          })
        ).loader;
    enrichedPlan = await enrichProductionPackageWaveApprovalPlanWithStagedContentHashes({
      plan: decision.plan,
      queueItemsByUnitKey: Object.fromEntries(snapshot.items.map((item) => [item.unitKey, item])),
      loadCandidates,
      useRecordedStagingHashes: Boolean(activeRelease),
      stagingEvidenceByUnitKey: approvalContext.stagingEvidenceByUnitKey
    });
  } catch (error) {
    console.error("Production package-wave staged content hash enrichment failed", error);
    return NextResponse.json(
      { ok: false, error: "Failed to compute staged content hashes for approval." },
      { status: 500 }
    );
  }

  try {
    const approved = await approveBatchProductionPackageWave({
      connectionString,
      projectKey: parsed.request.projectKey,
      plan: enrichedPlan,
      actor: auth.actor
    });

    return NextResponse.json({
      ok: true,
      decision: "approved",
      plan: {
        ...decision.plan,
        waveKey: approved.waveKey,
        unitKeys: approved.unitKeys
      },
      auditId: approved.auditId,
      waveId: approved.waveId,
      waveKey: approved.waveKey,
      unitKeys: approved.unitKeys,
      idempotentReplay: approved.idempotentReplay
    });
  } catch (error) {
    console.error("Production package-wave approval failed", error);
    return NextResponse.json(
      { ok: false, error: "Production package-wave approval could not be recorded." },
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
