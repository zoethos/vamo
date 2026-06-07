// Send FCM push to the caller's registered devices (T10.5 proof).
// Deploy: supabase functions deploy send-push
//
// Secrets:
//   FIREBASE_SERVICE_ACCOUNT — full Firebase service-account JSON string
//
// Body (JSON, optional):
//   { "title": "...", "body": "...", "route": "/trips/<uuid>" }
//
// Requires Authorization: Bearer <user JWT>. Never log device or invite tokens.

import { createClient } from "@supabase/supabase-js";
import {
  loadServiceAccount,
  sendPushToUserDevices,
} from "../_shared/fcm.ts";

interface PushBody {
  title?: string;
  body?: string;
  route?: string;
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

  let result;
  try {
    result = await sendPushToUserDevices(
      supabase,
      serviceAccount,
      userData.user.id,
      { title, body, route },
    );
  } catch (e) {
    const message = e instanceof Error ? e.message : "token exchange failed";
    return new Response(JSON.stringify({ ok: false, error: message }), {
      status: 502,
      headers: { "Content-Type": "application/json" },
    });
  }

  return new Response(
    JSON.stringify({
      ok: result.sent > 0,
      sent: result.sent,
      failed: result.failed,
      pruned: result.pruned,
    }),
    { headers: { "Content-Type": "application/json" } },
  );
});
