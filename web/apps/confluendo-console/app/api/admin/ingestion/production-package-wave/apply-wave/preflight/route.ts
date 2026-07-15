import { NextResponse, type NextRequest } from "next/server";
import {
  loadProductionPackageWaveConsumerApplyBatchPreflight,
  parseProductionPackageWaveApplyWavePreflightQuery
} from "@confluendo/ingestion-platform/core";
import { authorizeIngestionReadRequest } from "@/lib/ingestion-admin-auth";
import { getActiveControlEnvironmentConfig } from "@/lib/control-environment-server";

export const runtime = "nodejs";

export async function GET(request: NextRequest) {
  const parsed = parseProductionPackageWaveApplyWavePreflightQuery(
    Object.fromEntries(request.nextUrl.searchParams.entries())
  );
  if (!parsed.ok) {
    return NextResponse.json({ ok: false, error: parsed.error }, { status: 400 });
  }

  const auth = await authorizeIngestionReadRequest({
    projectKey: parsed.query.projectKey
  });
  if (!auth.ok) {
    return NextResponse.json(auth.body, { status: auth.status });
  }

  const environmentConfig = await getActiveControlEnvironmentConfig();
  if (environmentConfig?.environment !== "production") {
    return NextResponse.json(
      { ok: false, error: "Apply-to-Vamo preflight is available only in the Production workspace." },
      { status: 409 }
    );
  }
  const controlDb = environmentConfig.controlDatabaseUrl;
  const applyDb = environmentConfig.vamoProductionInboxApplyDatabaseUrl;
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
      proveApply: () => environmentConfig.vamoProductionInboxEnvironment === "production"
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
