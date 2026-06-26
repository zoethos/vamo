import "server-only";

import type { SupabaseClient } from "@supabase/supabase-js";
import type { NextRequest } from "next/server";
import { NextResponse } from "next/server";

import {
  getIngestionAdminPrincipal,
  readableAdminAccessFailure,
  type IngestionAdminFailureCode,
} from "./ingestion-admin-auth";
import { createSupabaseServerClient } from "./supabase-server";

type MfaRouteContext =
  | { ok: true; supabase: SupabaseClient }
  | {
      ok: false;
      response: NextResponse<{ ok: false; code: string; error: string }>;
    };

export async function requireMfaRouteContext(
  request: NextRequest
): Promise<MfaRouteContext> {
  const sameOrigin = requireSameOriginJson(request);
  if (!sameOrigin.ok) {
    return { ok: false, response: jsonFailure(sameOrigin.status, sameOrigin.code, sameOrigin.error) };
  }

  const resolution = await getIngestionAdminPrincipal("vamo");
  if (!resolution.ok) {
    return {
      ok: false,
      response: jsonFailure(
        adminFailureStatus(resolution.code),
        resolution.code,
        readableAdminAccessFailure(resolution.code)
      ),
    };
  }

  const supabase = await createSupabaseServerClient();
  if (!supabase) {
    return {
      ok: false,
      response: jsonFailure(
        503,
        "auth_not_configured",
        readableAdminAccessFailure("auth_not_configured")
      ),
    };
  }

  return { ok: true, supabase };
}

export function jsonFailure(
  status: number,
  code: string,
  error: string
): NextResponse<{ ok: false; code: string; error: string }> {
  return NextResponse.json({ ok: false, code, error }, { status });
}

export function normalizeAdminNextPath(value: unknown): string {
  if (typeof value !== "string" || !value.startsWith("/") || value.startsWith("//")) {
    return "/admin/ingestion";
  }
  return value;
}

export function readJsonString(value: unknown): string | undefined {
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : undefined;
}

function requireSameOriginJson(
  request: NextRequest
):
  | { ok: true }
  | { ok: false; status: number; code: string; error: string } {
  const contentType = request.headers.get("content-type") ?? "";
  if (!contentType.toLowerCase().includes("application/json")) {
    return {
      ok: false,
      status: 415,
      code: "json_required",
      error: "MFA requests must use application/json.",
    };
  }

  const origin = request.headers.get("origin");
  if (!origin) {
    return {
      ok: false,
      status: 403,
      code: "origin_required",
      error: "MFA requests must include a same-origin Origin header.",
    };
  }

  const requestedOrigin = originFromHostHeaders(request);
  const allowedOrigins = new Set([
    request.nextUrl.origin,
    ...(requestedOrigin ? [requestedOrigin] : []),
  ]);
  const parsedOrigin = parseOrigin(origin);
  if (!parsedOrigin || !allowedOrigins.has(parsedOrigin)) {
    return {
      ok: false,
      status: 403,
      code: "cross_origin_rejected",
      error: "Cross-origin MFA requests are not allowed.",
    };
  }

  const fetchSite = request.headers.get("sec-fetch-site");
  if (fetchSite && !["same-origin", "same-site", "none"].includes(fetchSite)) {
    return {
      ok: false,
      status: 403,
      code: "cross_site_rejected",
      error: "Cross-site MFA requests are not allowed.",
    };
  }

  return { ok: true };
}

function parseOrigin(value: string): string | undefined {
  try {
    return new URL(value).origin;
  } catch {
    return undefined;
  }
}

function originFromHostHeaders(request: NextRequest): string | undefined {
  const host = request.headers.get("host");
  if (!host) {
    return undefined;
  }
  const forwardedProto = request.headers.get("x-forwarded-proto")?.split(",")[0]?.trim();
  const protocol = forwardedProto || request.nextUrl.protocol.replace(":", "") || "https";
  return `${protocol}://${host}`;
}

function adminFailureStatus(code: IngestionAdminFailureCode): number {
  switch (code) {
    case "auth_not_configured":
    case "allowlist_not_configured":
    case "mfa_status_unavailable":
      return 503;
    case "not_authenticated":
      return 401;
    default:
      return 403;
  }
}
