// Daily trip lifecycle jobs — S17 / R3 (deemed close, reminders, unresolved).
// Deploy: supabase functions deploy trip-lifecycle-jobs --no-verify-jwt
// Schedule: daily cron in Dashboard; requires x-cron-secret header.
//
// Unlike scheduled-heartbeat, this MUST validate CRON_SECRET on every request.

import { createClient } from "@supabase/supabase-js";

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const secret = Deno.env.get("CRON_SECRET") ?? "";
  if (!secret || req.headers.get("x-cron-secret") !== secret) {
    return new Response("Unauthorized", { status: 401 });
  }

  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!url || !serviceKey) {
    return new Response("Missing Supabase env", { status: 500 });
  }

  const supabase = createClient(url, serviceKey);

  const { data: jobResult, error: jobError } = await supabase.rpc(
    "run_trip_lifecycle_jobs",
  );
  if (jobError) {
    console.error("run_trip_lifecycle_jobs failed", jobError);
    return new Response(JSON.stringify({ ok: false, error: jobError.message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }

  const { data: heartbeatId, error: hbError } = await supabase.rpc(
    "record_job_heartbeat",
    {
      p_job_name: "trip-lifecycle-jobs",
      p_detail: JSON.stringify(jobResult),
    },
  );
  if (hbError) {
    console.error("heartbeat failed", hbError);
  }

  return new Response(
    JSON.stringify({ ok: true, result: jobResult, heartbeatId }),
    { headers: { "Content-Type": "application/json" } },
  );
});
