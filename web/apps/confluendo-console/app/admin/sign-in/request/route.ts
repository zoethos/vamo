import { NextResponse, type NextRequest } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase-server";

const SIGN_IN_REQUEST_COOKIE = "confluendo_admin_sign_in_request";
const SIGN_IN_REQUEST_COOLDOWN_MS = 45_000;

export async function POST(request: NextRequest) {
  const formData = await request.formData();
  const email = readString(formData.get("email"));
  const method = normalizeSignInMethod(readString(formData.get("method")));
  const next = normalizeNextPath(readString(formData.get("next")));

  if (!email) {
    return redirectToSignIn(request, { error: "missing_email", method, next });
  }

  if (isDuplicateRequest(request, email, method)) {
    return redirectToSignIn(request, { sent: "1", email, method, next });
  }

  const supabase = await createSupabaseServerClient();
  if (!supabase) {
    return redirectToSignIn(request, { error: "auth_not_configured", method, next });
  }

  const callbackUrl = new URL("/admin/auth/callback", request.url);
  callbackUrl.searchParams.set("next", next);

  const { error } = await supabase.auth.signInWithOtp({
    email,
    options: {
      // Admin console access is provisioned-only; sign-in requests must never
      // create Supabase Auth users.
      shouldCreateUser: false,
      emailRedirectTo: callbackUrl.toString(),
    },
  });

  if (error) {
    const errorCode = signInRequestErrorCode(error);
    console.warn("Admin sign-in email request failed", summarizeAuthError(error));
    return redirectToSignIn(request, { error: errorCode, method, next });
  }

  const response = redirectToSignIn(request, { sent: "1", email, method, next });
  response.cookies.set(SIGN_IN_REQUEST_COOKIE, serializeRequestMarker(email, method), {
    httpOnly: true,
    maxAge: Math.ceil(SIGN_IN_REQUEST_COOLDOWN_MS / 1000),
    path: "/admin/sign-in",
    sameSite: "lax",
    secure: request.nextUrl.protocol === "https:",
  });
  return response;
}

function redirectToSignIn(
  request: NextRequest,
  params: Record<string, string | undefined>
): NextResponse {
  const url = new URL("/admin/sign-in", request.url);
  Object.entries(params).forEach(([key, value]) => {
    if (value) {
      url.searchParams.set(key, value);
    }
  });
  return NextResponse.redirect(url);
}

function readString(value: FormDataEntryValue | null): string | undefined {
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : undefined;
}

function normalizeNextPath(value: string | undefined): string {
  if (!value || !value.startsWith("/") || value.startsWith("//")) {
    return "/admin/ingestion";
  }
  return value;
}

function normalizeSignInMethod(value: string | undefined): "link" | "code" {
  return value === "code" ? "code" : "link";
}

function isDuplicateRequest(
  request: NextRequest,
  email: string,
  method: "link" | "code"
): boolean {
  const marker = request.cookies.get(SIGN_IN_REQUEST_COOKIE)?.value;
  if (!marker) {
    return false;
  }

  const [markerEmail, markerMethod, markerTimestamp] = marker.split("|");
  const requestedEmail = normalizeEmailForMarker(email);
  const timestamp = Number(markerTimestamp);

  if (
    markerEmail !== requestedEmail ||
    markerMethod !== method ||
    !Number.isFinite(timestamp)
  ) {
    return false;
  }

  return Date.now() - timestamp < SIGN_IN_REQUEST_COOLDOWN_MS;
}

function serializeRequestMarker(email: string, method: "link" | "code"): string {
  return `${normalizeEmailForMarker(email)}|${method}|${Date.now()}`;
}

function normalizeEmailForMarker(email: string): string {
  return encodeURIComponent(email.trim().toLowerCase());
}

function signInRequestErrorCode(error: unknown): string {
  if (isAuthRateLimit(error)) {
    return "rate_limited";
  }
  return "send_failed";
}

function isAuthRateLimit(error: unknown): boolean {
  const status = authErrorStatus(error);
  const message = error instanceof Error ? error.message.toLowerCase() : "";
  const code = authErrorCode(error)?.toLowerCase() ?? "";
  return (
    status === 429 ||
    code.includes("rate") ||
    message.includes("rate limit") ||
    message.includes("too many")
  );
}

function summarizeAuthError(error: unknown): Record<string, string | number> {
  const status = authErrorStatus(error);
  const code = authErrorCode(error);
  const message = error instanceof Error ? error.message : "Unknown auth error";
  return {
    ...(typeof status === "number" ? { status } : {}),
    ...(code ? { code } : {}),
    message,
  };
}

function authErrorStatus(error: unknown): number | undefined {
  if (!error || typeof error !== "object") {
    return undefined;
  }
  const status = (error as { status?: unknown }).status;
  return typeof status === "number" ? status : undefined;
}

function authErrorCode(error: unknown): string | undefined {
  if (!error || typeof error !== "object") {
    return undefined;
  }
  const code = (error as { code?: unknown }).code;
  return typeof code === "string" ? code : undefined;
}
