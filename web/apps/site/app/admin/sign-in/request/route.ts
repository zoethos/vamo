import { NextResponse, type NextRequest } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase-server";

export async function POST(request: NextRequest) {
  const formData = await request.formData();
  const email = readString(formData.get("email"));
  const next = normalizeNextPath(readString(formData.get("next")));

  if (!email) {
    return redirectToSignIn(request, { error: "missing_email", next });
  }

  const supabase = await createSupabaseServerClient();
  if (!supabase) {
    return redirectToSignIn(request, { error: "auth_not_configured", next });
  }

  const callbackUrl = new URL("/admin/auth/callback", request.url);
  callbackUrl.searchParams.set("next", next);

  const { error } = await supabase.auth.signInWithOtp({
    email,
    options: {
      emailRedirectTo: callbackUrl.toString(),
    },
  });

  if (error) {
    return redirectToSignIn(request, { error: "send_failed", next });
  }

  return redirectToSignIn(request, { sent: "1", email, next });
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
