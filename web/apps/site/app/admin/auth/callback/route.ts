import { NextResponse, type NextRequest } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase-server";

type EmailOtpType = "email" | "magiclink";

export async function GET(request: NextRequest) {
  const code = request.nextUrl.searchParams.get("code");
  const tokenHash = request.nextUrl.searchParams.get("token_hash");
  const otpType = normalizeEmailOtpType(request.nextUrl.searchParams.get("type"));
  const next = normalizeNextPath(request.nextUrl.searchParams.get("next") ?? undefined, request);

  if (!code && (!tokenHash || !otpType)) {
    return redirectToSignIn(request, "callback_failed", next);
  }

  const supabase = await createSupabaseServerClient();
  if (!supabase) {
    return redirectToSignIn(request, "auth_not_configured", next);
  }

  if (tokenHash && otpType) {
    const result = await verifyTokenHashWithFallback(supabase, tokenHash, otpType);
    if (result.error) {
      console.warn("Admin auth token-hash callback failed", {
        requestedType: otpType,
        attempts: result.attempts,
      });
      return redirectToSignIn(request, "callback_failed", next);
    }

    return NextResponse.redirect(new URL(next, request.url));
  }

  const { error } = await exchangeCodeForSession(supabase, code);
  if (error) {
    console.warn("Admin auth code callback failed", summarizeAuthError(error));
    return redirectToSignIn(request, callbackErrorCode(error), next);
  }

  return NextResponse.redirect(new URL(next, request.url));
}

async function verifyTokenHashWithFallback(
  supabase: NonNullable<Awaited<ReturnType<typeof createSupabaseServerClient>>>,
  tokenHash: string,
  preferredType: EmailOtpType
): Promise<{
  error: unknown | null;
  attempts: Array<{ type: EmailOtpType; error?: Record<string, unknown> }>;
}> {
  const fallbackType: EmailOtpType = preferredType === "email" ? "magiclink" : "email";
  const attempts: Array<{ type: EmailOtpType; error?: Record<string, unknown> }> = [];

  for (const type of [preferredType, fallbackType]) {
    const { error } = await supabase.auth.verifyOtp({
      token_hash: tokenHash,
      type,
    });

    if (!error) {
      attempts.push({ type });
      return { error: null, attempts };
    }

    attempts.push({ type, error: summarizeAuthError(error) });
  }

  return { error: new Error("Token hash verification failed"), attempts };
}

function redirectToSignIn(request: NextRequest, error: string, next: string): NextResponse {
  const url = new URL("/admin/sign-in", request.url);
  url.searchParams.set("error", error);
  url.searchParams.set("next", next);
  return NextResponse.redirect(url);
}

async function exchangeCodeForSession(
  supabase: NonNullable<Awaited<ReturnType<typeof createSupabaseServerClient>>>,
  code: string | null
): Promise<{ error: unknown | null }> {
  if (!code) {
    return { error: new Error("Missing auth code") };
  }

  try {
    return await supabase.auth.exchangeCodeForSession(code);
  } catch (error) {
    return { error };
  }
}

function normalizeEmailOtpType(value: string | null): EmailOtpType | null {
  return value === "email" || value === "magiclink" ? value : null;
}

function normalizeNextPath(value: string | undefined, request: NextRequest): string {
  if (!value || !value.startsWith("/") || value.startsWith("//")) {
    return normalizeSameOriginUrl(value, request);
  }
  return value;
}

function normalizeSameOriginUrl(value: string | undefined, request: NextRequest): string {
  if (!value) {
    return "/admin/ingestion";
  }
  try {
    const parsed = new URL(value);
    if (parsed.origin !== request.nextUrl.origin) {
      return "/admin/ingestion";
    }
    if (parsed.pathname === "/admin/auth/callback") {
      return normalizeNextPath(parsed.searchParams.get("next") ?? undefined, request);
    }
    return `${parsed.pathname}${parsed.search}${parsed.hash}`;
  } catch {
    return "/admin/ingestion";
  }
}

function callbackErrorCode(error: unknown): string {
  const message = error instanceof Error ? error.message.toLowerCase() : "";
  const code = authErrorCode(error)?.toLowerCase() ?? "";
  if (
    message.includes("code verifier") ||
    message.includes("pkce") ||
    code.includes("flow_state") ||
    code.includes("code_verifier")
  ) {
    return "link_session_mismatch";
  }
  return "callback_failed";
}

function summarizeAuthError(error: unknown): Record<string, unknown> {
  if (!error || typeof error !== "object") {
    return { message: String(error) };
  }
  const record = error as Record<string, unknown>;
  return {
    status: record.status,
    code: record.code,
    name: record.name,
    message: record.message,
  };
}

function authErrorCode(error: unknown): string | undefined {
  if (!error || typeof error !== "object") {
    return undefined;
  }
  const code = (error as { code?: unknown }).code;
  return typeof code === "string" ? code : undefined;
}
