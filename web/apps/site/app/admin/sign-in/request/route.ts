import { NextResponse, type NextRequest } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase-server";

export async function POST(request: NextRequest) {
  const formData = await request.formData();
  const email = readString(formData.get("email"));
  const method = normalizeSignInMethod(readString(formData.get("method")));
  const next = normalizeNextPath(readString(formData.get("next")));

  if (!email) {
    return redirectToSignIn(request, { error: "missing_email", method, next });
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

  return redirectToSignIn(request, { sent: "1", email, method, next });
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
