import { NextResponse, type NextRequest } from "next/server";
import {
  loadProductionPackageWaveConsumerApplyBatchPreflight,
  parseProductionPackageWaveApplyWavePreflightQuery
} from "@confluendo/ingestion-platform/core";
import { authorizeStagingCanaryRequest } from "@/lib/ingestion-admin-auth";

export const runtime = "nodejs";

export async function GET(request: NextRequest) {
  const parsed = parseProductionPackageWaveApplyWavePreflightQuery(
    Object.fromEntries(request.nextUrl.searchParams.entries())
  );
  if (!parsed.ok) {
    return NextResponse.json({ ok: false, error: parsed.error }, { status: 400 });
  }

  const auth = await authorizeStagingCanaryRequest({
    request,
    projectKey: parsed.query.projectKey
  });
  if (!auth.ok) {
    return NextResponse.json(auth.body, { status: auth.status });
  }

  const controlDb = process.env.INGESTION_CONTROL_DATABASE_URL?.trim();
  const applyDb = process.env.VAMO_PRODUCTION_INBOX_APPLY_DATABASE_URL?.trim();
  if (!controlDb || !applyDb) {
    return NextResponse.json(
      { ok: false, error: "Production inbox apply is not configured on the server." },
      { status: 503 }
    );
  }

  try {
    const result = await loadProductionPackageWaveConsumerApplyBatchPreflight({
      projectKey: parsed.query.projectKey,
      waveKey: parsed.query.waveKey,
      packageIds: parsed.query.packageIds,
      unitKeys: parsed.query.unitKeys,
      controlConnectionString: controlDb,
      applyConnectionString: applyDb,
      proveApply: () => process.env.VAMO_PRODUCTION_INBOX_ENVIRONMENT === "production"
    });

    if (!result.ok) {
      return NextResponse.json(
        { ok: false, decision: "blocked", blocks: result.blocks },
        { status: 409 }
      );
    }

    return NextResponse.json({
      ok: true,
      waveKey: result.waveKey,
      targets: result.targets.map((target) => ({
        unitKey: target.unitKey,
        packageId: target.packageId,
        checksum: target.preflight.checksum,
        itemCount: target.preflight.itemCount,
        pendingItemCount: target.preflight.pendingItemCount,
        targetTables: target.preflight.targetTables
      })),
      skippedAppliedPackageIds: result.skippedAppliedPackageIds,
      preflightSummary: result.preflightSummary
    });
  } catch (error) {
    console.error("Production package-wave batch apply preflight failed", error);
    return NextResponse.json(
      { ok: false, error: "Failed to load batch apply preflight." },
      { status: 500 }
    );
  }
}
