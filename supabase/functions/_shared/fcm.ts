// Shared FCM v1 helper for send-push and trip-lifecycle-jobs (S22).
// Never log device tokens or invite secrets.

import type { SupabaseClient } from "@supabase/supabase-js";
import { importPKCS8, SignJWT } from "jose";

const FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging";
const GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token";

export interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

export interface PushPayload {
  title: string;
  body: string;
  route: string;
}

export interface PushSendResult {
  sent: number;
  failed: number;
  pruned: number;
  skipped: number;
}

interface CachedAccessToken {
  token: string;
  expiresAtMs: number;
}

let accessTokenCache: CachedAccessToken | null = null;
let parsedServiceAccount: ServiceAccount | null = null;

export function loadServiceAccount(): ServiceAccount | null {
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

export async function getFcmAccessToken(sa: ServiceAccount): Promise<string> {
  const now = Date.now();
  if (accessTokenCache && now < accessTokenCache.expiresAtMs - 60_000) {
    return accessTokenCache.token;
  }

  const key = await importPKCS8(sa.private_key, "RS256");
  const assertion = await new SignJWT({ scope: FCM_SCOPE })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(sa.client_email)
    .setSubject(sa.client_email)
    .setAudience(GOOGLE_TOKEN_URL)
    .setIssuedAt()
    .setExpirationTime("1h")
    .sign(key);

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

function isUnregisteredToken(status: number, bodyText: string): boolean {
  if (status !== 404 && status !== 400) return false;
  const lower = bodyText.toLowerCase();
  return lower.includes("not_found") ||
    lower.includes("unregistered") ||
    lower.includes("registration-token-not-registered");
}

function isRetryableFcmStatus(status: number): boolean {
  return status === 429 || status >= 500;
}

function sendFcmV1(
  accessToken: string,
  projectId: string,
  deviceToken: string,
  payload: PushPayload,
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
        notification: { title: payload.title, body: payload.body },
        data: { route: payload.route },
      },
    }),
  });
}

export async function sendPushToUserDevices(
  supabase: SupabaseClient,
  sa: ServiceAccount,
  userId: string,
  payload: PushPayload,
): Promise<PushSendResult> {
  const { data: devices, error } = await supabase
    .from("push_devices")
    .select("id, fcm_token")
    .eq("user_id", userId);

  if (error || !devices?.length) {
    return { sent: 0, failed: error ? 1 : 0, pruned: 0, skipped: 0 };
  }

  const accessToken = await getFcmAccessToken(sa);
  let sent = 0;
  let failed = 0;
  let pruned = 0;

  for (const row of devices) {
    const deviceToken = row.fcm_token as string;
    const deviceId = row.id as string;
    let res: Response;
    try {
      res = await sendFcmV1(
        accessToken,
        sa.project_id,
        deviceToken,
        payload,
      );
    } catch {
      failed++;
      continue;
    }

    if (res.ok) {
      sent++;
      continue;
    }

    const bodyText = await res.text();
    if (isUnregisteredToken(res.status, bodyText)) {
      await supabase.from("push_devices").delete().eq("id", deviceId);
      pruned++;
      continue;
    }

    if (isRetryableFcmStatus(res.status)) {
      failed++;
      continue;
    }

    failed++;
  }

  return { sent, failed, pruned, skipped: 0 };
}
