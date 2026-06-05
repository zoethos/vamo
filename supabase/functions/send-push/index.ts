// Send FCM push to the caller's registered devices (T10.5 proof).
// Deploy: supabase functions deploy send-push
//
// Secrets:
//   FIREBASE_SERVICE_ACCOUNT — full Firebase service-account JSON string
//     (Firebase console → Project settings → Service accounts → Generate key)
//
// Body (JSON, optional):
//   { "title": "...", "body": "...", "route": "/trips/<uuid>" }
//
// Requires Authorization: Bearer <user JWT>. Never log device or invite tokens.

import { create, getNumericDate } from "https://deno.land/x/djwt@v3.0.2/mod.ts";
import { importPKCS8 } from "https://deno.land/x/djwt@v3.0.2/mod.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging";
const GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token";

interface PushBody {
  title?: string;
  body?: string;
  route?: string;
}

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

interface CachedAccessToken {
  token: string;
  expiresAtMs: number;
}

let accessTokenCache: CachedAccessToken | null = null;
let parsedServiceAccount: ServiceAccount | null = null;

function loadServiceAccount(): ServiceAccount | null {
  if (parsedServiceAccount) return parsedServiceAccount;
  const raw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT")?.trim();
  if (!raw) return null;
  try {
    const sa = JSON.parse(raw) as ServiceAccount;
    if (!sa.project_id || !sa.client_email || !sa.private_key) {
      return null;
    }
    parsedServiceAccount = sa;
    return sa;
  } catch {
    return null;
  }
}

async function getFcmAccessToken(sa: ServiceAccount): Promise<string> {
  const now = Date.now();
  if (accessTokenCache && now < accessTokenCache.expiresAtMs - 60_000) {
    return accessTokenCache.token;
  }

  const key = await importPKCS8(sa.private_key, "RS256");
  const assertion = await create(
    { alg: "RS256", typ: "JWT" },
    {
      iss: sa.client_email,
      sub: sa.client_email,
      aud: GOOGLE_TOKEN_URL,
      iat: getNumericDate(0),
      exp: getNumericDate(3600),
      scope: FCM_SCOPE,
    },
    key,
  );

  const tokenRes = await fetch(GOOGLE_TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });

  if (!tokenRes.ok) {
    throw new Error(`Google token exchange failed (${tokenRes.status})`);
  }

  const tokenBody = await tokenRes.json() as {
    access_token?: string;
    expires_in?: number;
  };
  if (!tokenBody.access_token) {
    throw new Error("Google token response missing access_token");
  }

  const ttlSec = tokenBody.expires_in ?? 3600;
  accessTokenCache = {
    token: tokenBody.access_token,
    expiresAtMs: now + ttlSec * 1000,
  };
  return accessTokenCache.token;
}

async function sendFcmV1(
  accessToken: string,
  projectId: string,
  deviceToken: string,
  title: string,
  body: string,
  route: string,
): Promise<Response> {
  const url =
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;
  return fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      message: {
        token: deviceToken,
        notification: { title, body },
        data: { route },
      },
    }),
  });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    return new Response("Unauthorized", { status: 401 });
  }

  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const anon = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  if (!url || !anon) {
    return new Response("Missing Supabase env", { status: 500 });
  }

  const serviceAccount = loadServiceAccount();
  if (!serviceAccount) {
    return new Response("FIREBASE_SERVICE_ACCOUNT not configured", {
      status: 503,
    });
  }

  const jwt = authHeader.slice("Bearer ".length);
  const supabase = createClient(url, anon, {
    global: { headers: { Authorization: `Bearer ${jwt}` } },
  });

  const { data: userData, error: userError } = await supabase.auth.getUser(jwt);
  if (userError || !userData.user) {
    return new Response("Unauthorized", { status: 401 });
  }

  let payload: PushBody = {};
  try {
    const text = await req.text();
    if (text) payload = JSON.parse(text) as PushBody;
  } catch {
    return new Response("Invalid JSON", { status: 400 });
  }

  const title = payload.title ?? "Vamo";
  const body = payload.body ?? "Test notification";
  const route = payload.route ?? "/trips";

  const { data: devices, error: devError } = await supabase
    .from("push_devices")
    .select("fcm_token")
    .eq("user_id", userData.user.id);

  if (devError) {
    return new Response(JSON.stringify({ ok: false, error: devError.message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }

  if (!devices?.length) {
    return new Response(JSON.stringify({ ok: false, error: "no devices registered" }), {
      status: 404,
      headers: { "Content-Type": "application/json" },
    });
  }

  let accessToken: string;
  try {
    accessToken = await getFcmAccessToken(serviceAccount);
  } catch (e) {
    const message = e instanceof Error ? e.message : "token exchange failed";
    return new Response(JSON.stringify({ ok: false, error: message }), {
      status: 502,
      headers: { "Content-Type": "application/json" },
    });
  }

  let sent = 0;
  let failed = 0;

  for (const row of devices) {
    const deviceToken = row.fcm_token as string;
    const res = await sendFcmV1(
      accessToken,
      serviceAccount.project_id,
      deviceToken,
      title,
      body,
      route,
    );
    if (res.ok) {
      sent++;
    } else {
      failed++;
    }
  }

  return new Response(
    JSON.stringify({ ok: sent > 0, sent, failed }),
    { headers: { "Content-Type": "application/json" } },
  );
});
