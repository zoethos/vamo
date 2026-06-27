import { NextResponse, type NextRequest } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase-server";

export async function POST(request: NextRequest) {
  const formData = await request.formData();
  const email = readString(formData.get("email"));
  const token = normalizeOtpCode(readString(formData.get("otp")));
  const next = normalizeNextPath(readString(formData.get("next")));

  if (!email) {
    return redirectToSignIn(request, { error: "missing_email", sent: "1", next });
  }

  if (!token) {
    return redirectToSignIn(request, { error: "otp_missing", sent: "1", email, next });
  }

  const supabase = await createSupabaseServerClient();

  if (!supabase) {
    return redirectToSignIn(request, {
      error: "auth_not_configured",
      sent: "1",
      email,
      next,
    });
  }

  const { error } = await supabase.auth.verifyOtp({
    email,
    token,
    type: "email",
  });

  if (error) {
    console.warn("Admin email OTP verification failed", summarizeAuthError(error));
    return redirectToSignIn(request, { error: "otp_failed", sent: "1", email, next });
  }

  return NextResponse.redirect(new URL(next, request.url));
}

function redirectToSignIn(
  request: NextRequest,
  params: Record<string, string | undefined>,
): NextResponse {
  const url = new URL("/admin/sign-in", request.url);
  for (const [key, value] of Object.entries(params)) {
    if (value) {
      url.searchParams.set(key, value);
    }
  }
  return NextResponse.redirect(url);
}

function readString(value: FormDataEntryValue | null): string | undefined {
  if (typeof value !== "string") {
    return undefined;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

function normalizeNextPath(value: string | undefined): string {
  if (!value || !value.startsWith("/") || value.startsWith("//")) {
    return "/admin/ingestion";
  }
  return value;
}

function normalizeOtpCode(value: string | undefined): string | undefined {
  const normalized = value?.replace(/[\s-]+/g, "") ?? "";
  return normalized.length > 0 ? normalized : undefined;
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
