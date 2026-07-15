import { createServerClient, type CookieOptions } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import { CONTROL_ENVIRONMENT_COOKIE, parseControlEnvironment } from "./control-environment";
import { getDefaultControlEnvironment } from "./control-environment-config";
import { getSupabasePublicConfigForEnvironment } from "./supabase-config";

const openAdminPaths = new Set([
  "/admin/sign-in",
  "/admin/sign-in/request",
  "/admin/sign-in/verify",
  "/admin/auth/callback",
  "/admin/sign-out",
]);

export function isOpenAdminPath(pathname: string): boolean {
  return openAdminPaths.has(pathname);
}

export async function requireAdminSession(request: NextRequest): Promise<NextResponse> {
  const pathname = request.nextUrl.pathname;

  if (!pathname.startsWith("/admin/") || isOpenAdminPath(pathname)) {
    return NextResponse.next();
  }

  const signInUrl = new URL("/admin/sign-in", request.url);
  signInUrl.searchParams.set("next", `${request.nextUrl.pathname}${request.nextUrl.search}`);

  const environment =
    parseControlEnvironment(request.cookies.get(CONTROL_ENVIRONMENT_COOKIE)?.value) ??
    getDefaultControlEnvironment();
  const config = getSupabasePublicConfigForEnvironment(environment);
  if (!config) {
    signInUrl.searchParams.set("reason", "auth_not_configured");
    return NextResponse.redirect(signInUrl);
  }

  let response = NextResponse.next({
    request,
  });

  const supabase = createServerClient(config.url, config.publishableKey, {
    cookies: {
      getAll() {
        return request.cookies.getAll();
      },
      setAll(cookiesToSet: { name: string; value: string; options: CookieOptions }[]) {
        cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value));
        response = NextResponse.next({
          request,
        });
        cookiesToSet.forEach(({ name, value, options }) => {
          response.cookies.set(name, value, options);
        });
      },
    },
  });

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.redirect(signInUrl);
  }

  return response;
}
