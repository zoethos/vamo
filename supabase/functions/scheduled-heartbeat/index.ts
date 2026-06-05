// No-op scheduled job proof — S16 / Wave 2 open question resolution.
// Deploy: supabase functions deploy scheduled-heartbeat --no-verify-jwt
// Schedule in Dashboard → Edge Functions → scheduled-heartbeat → Cron: 0 * * * *
// (hourly). Uses service role to write job_heartbeats.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!url || !serviceKey) {
    return new Response("Missing Supabase env", { status: 500 });
  }

  const supabase = createClient(url, serviceKey);
  const { data, error } = await supabase.rpc("record_job_heartbeat", {
    p_job_name: "scheduled-heartbeat",
    p_detail: "edge noop",
  });

  if (error) {
    console.error("heartbeat failed", error);
    return new Response(JSON.stringify({ ok: false, error: error.message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }

  return new Response(JSON.stringify({ ok: true, id: data }), {
    headers: { "Content-Type": "application/json" },
  });
});
