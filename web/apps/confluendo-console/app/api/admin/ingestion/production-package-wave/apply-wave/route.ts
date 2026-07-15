import { NextResponse, type NextRequest } from "next/server";
import {
  executeProductionPackageWaveConsumerApplyBatch,
  parseProductionPackageWaveApplyWaveRequest
} from "@confluendo/ingestion-platform/core";
import { authorizeStagingCanaryRequest } from "@/lib/ingestion-admin-auth";
import { getActiveControlEnvironmentConfig } from "@/lib/control-environment-server";

export const runtime = "nodejs";

/**
 * Production package-wave batch consumer apply endpoint (IP-18.8.4).
 *
 * Applies multiple delivered inbox packages sequentially via the existing
 * least-privilege apply adapter. No writer DSN and no direct target-table writes.
 */
export async function POST(request: NextRequest) {
  const body = await readJsonBody(request);
  if (!body.ok) {
    return NextResponse.json({ ok: false, error: body.error }, { status: 400 });
  }

  const parsed = parseProductionPackageWaveApplyWaveRequest(body.value);
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
      { ok: false, error: "Apply to Vamo is available only in the Production workspace." },
      { status: 409 }
    );
  }
  const controlDb = environmentConfig.controlDatabaseUrl;
  const applyDb = environmentConfig.vamoProductionInboxApplyDatabaseUrl;

  if (!controlDb) {
    return NextResponse.json(
      { ok: false, error: "Ingestion control database URL is not configured." },
      { status: 503 }
    );
  }
  if (!applyDb) {
    return NextResponse.json(
      { ok: false, error: "VAMO_PRODUCTION_INBOX_APPLY_DATABASE_URL is not configured." },
      { status: 503 }
    );
  }
  if (environmentConfig.vamoProductionInboxWriterDatabaseUrl) {
    return NextResponse.json(
      {
        ok: false,
        code: "writer_dsn_present",
        error: "Batch apply route must not run with production inbox writer DSN configured."
      },
      { status: 503 }
    );
  }

  try {
    const result = await executeProductionPackageWaveConsumerApplyBatch({
      projectKey: parsed.request.projectKey,
      waveKey: parsed.request.waveKey,
      auditReason: parsed.request.auditReason,
      packageIds: parsed.request.packageIds,
      unitKeys: parsed.request.unitKeys,
      principal: auth.principal,
      actor: auth.actor,
      controlConnectionString: controlDb,
      applyConnectionString: applyDb,
      proveApply: () => environmentConfig.vamoProductionInboxEnvironment === "production"
    });

    if (!result.ok) {
      if (result.blocks) {
        return NextResponse.json(
          {
            ok: false,
            decision: "blocked",
            blocks: result.blocks,
            failedPackageId: result.failedPackageId,
            applyResult: result.applyResult
          },
          { status: 409 }
        );
      }
      return NextResponse.json(
        {
          ok: false,
          decision: "failed",
          error: result.message ?? "Batch consumer apply failed.",
          failedPackageId: result.failedPackageId,
          applyResult: result.applyResult
        },
        { status: 422 }
      );
    }

    return NextResponse.json({
      ok: true,
      decision: "applied",
      waveKey: result.waveKey,
      appliedPackageIds: result.appliedPackageIds,
      skippedAppliedPackageIds: result.skippedAppliedPackageIds,
      auditIds: result.auditIds,
      applyResults: result.applyResults,
      preflightSummary: result.preflightSummary
    });
  } catch (error) {
    console.error("Production package-wave batch consumer apply failed", error);
    return NextResponse.json(
      { ok: false, error: "Production package-wave batch consumer apply could not be completed." },
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
