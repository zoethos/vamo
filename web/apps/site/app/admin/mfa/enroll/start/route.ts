import { NextResponse, type NextRequest } from "next/server";

import {
  jsonFailure,
  normalizeAdminNextPath,
  readJsonString,
  requireMfaRouteContext,
} from "@/lib/ingestion-admin-mfa-route";

export const dynamic = "force-dynamic";

export async function POST(request: NextRequest) {
  const context = await requireMfaRouteContext(request);
  if (!context.ok) {
    return context.response;
  }

  let body: Record<string, unknown>;
  try {
    body = (await request.json()) as Record<string, unknown>;
  } catch {
    return jsonFailure(400, "invalid_json", "MFA enrollment requests must include valid JSON.");
  }

  const next = normalizeAdminNextPath(body.next);
  const friendlyName = readJsonString(body.friendlyName) ?? "Confluendo operator console";

  const { data, error } = await context.supabase.auth.mfa.enroll({
    factorType: "totp",
    friendlyName,
    issuer: "Confluendo",
  });

  if (error || !data?.totp) {
    return jsonFailure(
      502,
      "mfa_enroll_failed",
      "Authenticator enrollment could not be started. Try again."
    );
  }

  return NextResponse.json({
    ok: true,
    next,
    factorId: data.id,
    qrCode: data.totp.qr_code,
    secret: data.totp.secret,
    uri: data.totp.uri,
  });
}
