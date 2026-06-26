import { NextResponse, type NextRequest } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase-server";

export async function GET(request: NextRequest) {
  const code = request.nextUrl.searchParams.get("code");
  const next = normalizeNextPath(request.nextUrl.searchParams.get("next") ?? undefined);

  if (!code) {
    return redirectToSignIn(request, "callback_failed", next);
  }

  const supabase = await createSupabaseServerClient();
  if (!supabase) {
    return redirectToSignIn(request, "auth_not_configured", next);
  }

  const { error } = await supabase.auth.exchangeCodeForSession(code);
  if (error) {
    return redirectToSignIn(request, "callback_failed", next);
  }

  return NextResponse.redirect(new URL(next, request.url));
}

function redirectToSignIn(request: NextRequest, error: string, next: string): NextResponse {
  const url = new URL("/admin/sign-in", request.url);
  url.searchParams.set("error", error);
  url.searchParams.set("next", next);
  return NextResponse.redirect(url);
}

function normalizeNextPath(value: string | undefined): string {
  if (!value || !value.startsWith("/") || value.startsWith("//")) {
    return "/admin/ingestion";
  }
  return value;
}
