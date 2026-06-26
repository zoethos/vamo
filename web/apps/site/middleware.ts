import { NextResponse, type NextRequest } from "next/server";
import { requireAdminSession } from "@/lib/supabase-middleware";

export async function middleware(request: NextRequest) {
  if (request.nextUrl.pathname.startsWith("/j/")) {
    const response = NextResponse.next();
    response.headers.set("Cache-Control", "private, no-store, max-age=0");
    return response;
  }

  if (request.nextUrl.pathname.startsWith("/admin/")) {
    return requireAdminSession(request);
  }

  return NextResponse.next();
}

export const config = {
  matcher: ["/j/:path*", "/admin/:path*"],
};
