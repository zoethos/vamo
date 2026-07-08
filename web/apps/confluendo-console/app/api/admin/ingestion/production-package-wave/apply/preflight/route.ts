import { NextResponse, type NextRequest } from "next/server";
import {
  evaluateProductionPackageConsumerApplyPreflight,
  loadProductionPackageConsumerApplyPreflight,
  parseProductionPackageWaveApplyPreflightQuery
} from "@confluendo/ingestion-platform/core";
import { authorizeStagingCanaryRequest } from "@/lib/ingestion-admin-auth";

export const runtime = "nodejs";

/**
 * Production package-wave consumer apply preflight (IP-18.6.6).
 *
 * Read-only inbox preflight for confirmation UI. Never executes apply.
 */
export async function GET(request: NextRequest) {
  const parsed = parseProductionPackageWaveApplyPreflightQuery({
    packageId: request.nextUrl.searchParams.get("packageId"),
    projectKey: request.nextUrl.searchParams.get("projectKey")
  });
  if (!parsed.ok) {
    return NextResponse.json({ ok: false, error: parsed.error }, { status: 400 });
  }

  const auth = await authorizeStagingCanaryRequest({
    request,
    projectKey: parsed.projectKey
  });
  if (!auth.ok) {
    return NextResponse.json(auth.body, { status: auth.status });
  }

  const applyDb = process.env.VAMO_PRODUCTION_INBOX_APPLY_DATABASE_URL?.trim();
  if (!applyDb) {
    return NextResponse.json(
      { ok: false, error: "VAMO_PRODUCTION_INBOX_APPLY_DATABASE_URL is not configured." },
      { status: 503 }
    );
  }

  try {
    const loaded = await loadProductionPackageConsumerApplyPreflight({
      packageId: parsed.packageId,
      applyConnectionString: applyDb,
      proveApply: () => process.env.VAMO_PRODUCTION_INBOX_ENVIRONMENT === "production"
    });
    if (!loaded.ok) {
      return NextResponse.json(
        { ok: false, error: loaded.message, code: loaded.code },
        { status: loaded.code === "package_not_found" ? 404 : 422 }
      );
    }

    const packageBlocks = evaluateProductionPackageConsumerApplyPreflight(loaded.preflight);

    return NextResponse.json({
      ok: true,
      preflight: loaded.preflight,
      eligible: packageBlocks.length === 0,
      blocks: packageBlocks
    });
  } catch (error) {
    console.error("Production package consumer apply preflight failed", error);
    return NextResponse.json(
      { ok: false, error: "Production package consumer apply preflight could not be loaded." },
      { status: 500 }
    );
  }
}
