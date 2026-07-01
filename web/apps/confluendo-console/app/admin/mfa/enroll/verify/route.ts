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
    return jsonFailure(400, "invalid_json", "MFA verification requests must include valid JSON.");
  }

  const factorId = readJsonString(body.factorId);
  const code = normalizeCode(readJsonString(body.code));
  const next = normalizeAdminNextPath(body.next);

  if (!factorId || !code) {
    return jsonFailure(400, "missing_code", "Enter the six-digit code from your authenticator app.");
  }

  const { error } = await context.supabase.auth.mfa.challengeAndVerify({
    factorId,
    code,
  });

  if (error) {
    return jsonFailure(403, "mfa_verify_failed", "The authenticator code could not be verified.");
  }

  return NextResponse.json({ ok: true, next });
}

function normalizeCode(value: string | undefined): string | undefined {
  const code = value?.replace(/\s+/g, "");
  return code && /^\d{6}$/.test(code) ? code : undefined;
}
