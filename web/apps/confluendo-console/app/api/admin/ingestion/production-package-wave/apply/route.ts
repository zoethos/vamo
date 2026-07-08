import { NextResponse, type NextRequest } from "next/server";
import {
  executeProductionPackageConsumerApply,
  loadProductionPackageConsumerApplyPreflight,
  parseProductionPackageWaveApplyRequest
} from "@confluendo/ingestion-platform/core";
import { authorizeStagingCanaryRequest } from "@/lib/ingestion-admin-auth";

export const runtime = "nodejs";

/**
 * Production package-wave consumer apply endpoint (IP-18.6.6).
 *
 * Invokes Vamo's apply_confluendo_shipment boundary only. No direct product-table
 * writes and no production inbox delivery.
 */
export async function POST(request: NextRequest) {
  const body = await readJsonBody(request);
  if (!body.ok) {
    return NextResponse.json({ ok: false, error: body.error }, { status: 400 });
  }

  const parsed = parseProductionPackageWaveApplyRequest(body.value);
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

  const controlDb = process.env.INGESTION_CONTROL_DATABASE_URL?.trim();
  const applyDb = process.env.VAMO_PRODUCTION_INBOX_APPLY_DATABASE_URL?.trim();

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

  try {
    const result = await executeProductionPackageConsumerApply({
      projectKey: parsed.request.projectKey,
      packageId: parsed.request.packageId,
      auditReason: parsed.request.auditReason,
      principal: auth.principal,
      actor: auth.actor,
      controlConnectionString: controlDb,
      applyConnectionString: applyDb,
      proveApply: () => process.env.VAMO_PRODUCTION_INBOX_ENVIRONMENT === "production"
    });

    if (!result.ok) {
      if (result.blocks) {
        return NextResponse.json(
          {
            ok: false,
            decision: "blocked",
            blocks: result.blocks,
            preflight: result.preflight,
            applyResult: result.applyResult,
            applyLog: result.applyLog,
            itemErrors: result.itemErrors
          },
          { status: 409 }
        );
      }
      if (result.message) {
        console.error("Production package consumer apply adapter failed", {
          packageId: parsed.request.packageId,
          message: result.message
        });
      }
      return NextResponse.json(
        {
          ok: false,
          decision: "failed",
          error: "Consumer apply failed. Review apply evidence and server logs.",
          applyResult: result.applyResult,
          preflight: result.preflight,
          applyLog: result.applyLog,
          itemErrors: result.itemErrors
        },
        { status: 422 }
      );
    }

    return NextResponse.json({
      ok: true,
      decision: "applied",
      packageId: result.packageId,
      auditId: result.auditId,
      applyResult: result.applyResult,
      preflight: result.preflight,
      idempotentReplay: result.idempotentReplay
    });
  } catch (error) {
    console.error("Production package consumer apply failed", error);
    return NextResponse.json(
      { ok: false, error: "Production package consumer apply could not be completed." },
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
