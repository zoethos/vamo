import { NextResponse, type NextRequest } from "next/server";
import {
  CONTROL_ENVIRONMENT_COOKIE,
  isControlEnvironment
} from "@/lib/control-environment";
import { getControlEnvironmentConfig } from "@/lib/control-environment-config";
import { requireSameOriginJsonMutation } from "@/lib/ingestion-admin-auth";

export const runtime = "nodejs";

export async function POST(request: NextRequest) {
  const csrf = requireSameOriginJsonMutation(request);
  if (!csrf.ok) {
    return NextResponse.json(csrf.body, { status: csrf.status });
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ ok: false, error: "Request body must be valid JSON." }, { status: 400 });
  }

  const environment =
    typeof body === "object" && body !== null && !Array.isArray(body)
      ? (body as { environment?: unknown }).environment
      : undefined;
  if (!isControlEnvironment(environment)) {
    return NextResponse.json({ ok: false, error: "Choose Staging or Production." }, { status: 400 });
  }
  if (!getControlEnvironmentConfig(environment)) {
    return NextResponse.json(
      { ok: false, error: `${environment === "production" ? "Production" : "Staging"} is not configured.` },
      { status: 503 }
    );
  }

  const response = NextResponse.json({ ok: true, environment });
  response.cookies.set(CONTROL_ENVIRONMENT_COOKIE, environment, {
    httpOnly: true,
    sameSite: "lax",
    secure: process.env.NODE_ENV === "production",
    path: "/",
    maxAge: 60 * 60 * 24 * 30
  });
  return response;
}
