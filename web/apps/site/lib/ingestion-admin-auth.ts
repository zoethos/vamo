import "server-only";

import { redirect } from "next/navigation";
import type { NextRequest } from "next/server";
import {
  adminPrincipalAuditContext,
  authorizeAdminCommand,
  authorizeAdminDashboard,
  resolvePostgresAdminPrincipal,
  type AdminAssuranceLevel,
  type AdminAuthFailureCode,
  type AdminPrincipal
} from "@vamo/ingestion-platform/admin-auth";
import type { IngestionCommandKind } from "@vamo/ingestion-platform/control-api";

import { createSupabaseServerClient } from "./supabase-server";

export type IngestionAdminFailureCode =
  | AdminAuthFailureCode
  | "auth_not_configured"
  | "not_authenticated"
  | "allowlist_not_configured"
  | "mfa_status_unavailable";

export type IngestionAdminResolution =
  | { ok: true; principal: AdminPrincipal }
  | { ok: false; code: IngestionAdminFailureCode };

type AmrEntry = {
  method?: string;
  timestamp?: number;
};

const firstFactorMethods = new Set([
  "anonymous",
  "email",
  "invite",
  "magiclink",
  "oauth",
  "otp",
  "password",
  "recovery",
  "sms",
  "sso"
]);

export async function getIngestionAdminPrincipal(
  projectKey = "vamo"
): Promise<IngestionAdminResolution> {
  const supabase = await createSupabaseServerClient();
  if (!supabase) {
    return { ok: false, code: "auth_not_configured" };
  }

  const {
    data: { user },
    error: userError
  } = await supabase.auth.getUser();
  if (userError || !user) {
    return { ok: false, code: "not_authenticated" };
  }

  const connectionString = process.env.INGESTION_CONTROL_DATABASE_URL?.trim();
  if (!connectionString) {
    return { ok: false, code: "allowlist_not_configured" };
  }

  const [aalResult, factorsResult] = await Promise.all([
    supabase.auth.mfa.getAuthenticatorAssuranceLevel(),
    supabase.auth.mfa.listFactors()
  ]);

  if (aalResult.error || factorsResult.error) {
    return { ok: false, code: "mfa_status_unavailable" };
  }

  const assuranceLevel: AdminAssuranceLevel =
    aalResult.data.currentLevel === "aal2" ? "aal2" : "aal1";
  const hasVerifiedMfaFactor =
    factorsResult.data.all.some((factor) => factor.status === "verified") ||
    factorsResult.data.totp.length > 0 ||
    factorsResult.data.phone.length > 0;

  return resolvePostgresAdminPrincipal({
    connectionString,
    provider: "supabase",
    providerUserId: user.id,
    email: user.email ?? "",
    assuranceLevel,
    hasVerifiedMfaFactor,
    stepUpSatisfiedAt: latestMfaAuthenticationAt(
      aalResult.data.currentAuthenticationMethods
    ),
    projectKey
  });
}

export async function requireIngestionAdminPrincipal(input: {
  projectKey?: string;
  nextPath: string;
}): Promise<AdminPrincipal> {
  const resolution = await getIngestionAdminPrincipal(input.projectKey ?? "vamo");
  if (!resolution.ok) {
    redirect(adminAccessRedirectPath(resolution.code, input.nextPath));
  }
  return resolution.principal;
}

export async function requireIngestionDashboardAccess(input: {
  projectKey?: string;
  nextPath: string;
}): Promise<AdminPrincipal> {
  const principal = await requireIngestionAdminPrincipal(input);
  const decision = authorizeAdminDashboard(principal);
  if (!decision.ok) {
    redirect(adminAccessRedirectPath(decision.code, input.nextPath));
  }
  return principal;
}

export async function authorizeIngestionCommandRequest(input: {
  request: NextRequest;
  projectKey: string;
  command: IngestionCommandKind;
}): Promise<
  | {
      ok: true;
      actor: { type: "operator"; id: string };
      auditContext: Record<string, unknown>;
    }
  | { ok: false; status: number; body: { ok: false; error: string; code: string } }
> {
  const csrf = requireSameOriginJsonMutation(input.request);
  if (!csrf.ok) {
    return csrf;
  }

  const resolution = await getIngestionAdminPrincipal(input.projectKey);
  if (!resolution.ok) {
    return adminJsonFailure(resolution.code);
  }

  const decision = authorizeAdminCommand({
    principal: resolution.principal,
    projectKey: input.projectKey,
    command: input.command
  });
  if (!decision.ok) {
    return adminJsonFailure(decision.code);
  }

  return {
    ok: true,
    actor: {
      type: "operator",
      id: `supabase:${resolution.principal.userId}`
    },
    auditContext: adminPrincipalAuditContext(resolution.principal)
  };
}

export function adminAccessRedirectPath(
  code: IngestionAdminFailureCode,
  nextPath: string
): string {
  const next = normalizeNextPath(nextPath);
  if (code === "auth_not_configured") {
    return `/admin/sign-in?reason=auth_not_configured&next=${encodeURIComponent(next)}`;
  }
  if (code === "not_authenticated") {
    return `/admin/sign-in?next=${encodeURIComponent(next)}`;
  }
  if (code === "mfa_enrollment_required") {
    return `/admin/mfa/enroll?next=${encodeURIComponent(next)}`;
  }
  if (code === "mfa_challenge_required" || code === "fresh_step_up_required") {
    return `/admin/mfa/challenge?reason=${code}&next=${encodeURIComponent(next)}`;
  }
  return `/admin/access-denied?reason=${code}&next=${encodeURIComponent(next)}`;
}

export function readableAdminAccessFailure(code: string): string {
  switch (code) {
    case "allowlist_not_configured":
      return "The platform allowlist database is not configured for this environment.";
    case "auth_not_configured":
      return "Supabase auth is not configured for this environment.";
    case "not_allowlisted":
      return "This Supabase account is not on the ingestion admin allowlist.";
    case "suspended":
      return "This admin allowlist entry is suspended.";
    case "expired":
      return "This admin allowlist entry has expired.";
    case "scope_denied":
      return "This admin account is not scoped to this ingestion project.";
    case "mfa_status_unavailable":
      return "Supabase MFA status could not be verified. Try again before using operator controls.";
    case "mfa_enrollment_required":
      return "Enroll an authenticator app before using operator controls.";
    case "mfa_challenge_required":
      return "Complete MFA step-up before using operator controls.";
    case "fresh_step_up_required":
      return "Reset requires a fresh MFA challenge.";
    case "role_denied":
      return "This admin role cannot perform that command.";
    default:
      return "Access to the ingestion admin console is restricted.";
  }
}

function requireSameOriginJsonMutation(
  request: NextRequest
):
  | { ok: true }
  | { ok: false; status: number; body: { ok: false; error: string; code: string } } {
  const contentType = request.headers.get("content-type") ?? "";
  if (!contentType.toLowerCase().includes("application/json")) {
    return {
      ok: false,
      status: 415,
      body: {
        ok: false,
        code: "json_required",
        error: "Command requests must use application/json."
      }
    };
  }

  const origin = request.headers.get("origin");
  if (!origin) {
    return {
      ok: false,
      status: 403,
      body: {
        ok: false,
        code: "origin_required",
        error: "Command requests must include a same-origin Origin header."
      }
    };
  }

  const requestedOrigin = originFromHostHeaders(request);
  const allowedOrigins = new Set([
    request.nextUrl.origin,
    ...(requestedOrigin ? [requestedOrigin] : [])
  ]);
  const parsedOrigin = parseOrigin(origin);

  if (!parsedOrigin || !allowedOrigins.has(parsedOrigin)) {
    return {
      ok: false,
      status: 403,
      body: {
        ok: false,
        code: "cross_origin_rejected",
        error: "Cross-origin command requests are not allowed."
      }
    };
  }

  const fetchSite = request.headers.get("sec-fetch-site");
  if (fetchSite && !["same-origin", "same-site", "none"].includes(fetchSite)) {
    return {
      ok: false,
      status: 403,
      body: {
        ok: false,
        code: "cross_site_rejected",
        error: "Cross-site command requests are not allowed."
      }
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

function adminJsonFailure(
  code: IngestionAdminFailureCode
): { ok: false; status: number; body: { ok: false; error: string; code: string } } {
  return {
    ok: false,
    status: adminFailureStatus(code),
    body: {
      ok: false,
      code,
      error: readableAdminAccessFailure(code)
    }
  };
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

function latestMfaAuthenticationAt(
  methods: AmrEntry[] | string[] | undefined
): string | undefined {
  if (!Array.isArray(methods)) {
    return undefined;
  }

  const latestSeconds = methods.reduce<number | undefined>((latest, entry) => {
    if (typeof entry !== "object" || entry === null) {
      return latest;
    }
    const method = typeof entry.method === "string" ? entry.method.toLowerCase() : "";
    if (!method || firstFactorMethods.has(method)) {
      return latest;
    }
    if (typeof entry.timestamp !== "number" || !Number.isFinite(entry.timestamp)) {
      return latest;
    }
    return latest === undefined ? entry.timestamp : Math.max(latest, entry.timestamp);
  }, undefined);

  return latestSeconds === undefined
    ? undefined
    : new Date(latestSeconds * 1000).toISOString();
}

function normalizeNextPath(value: string): string {
  if (!value || !value.startsWith("/") || value.startsWith("//")) {
    return "/admin/ingestion";
  }
  return value;
}
