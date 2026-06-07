// Daily trip lifecycle jobs — S17/S22 (notice, reminders, deemed close, settle nudge).
// Deploy: supabase functions deploy trip-lifecycle-jobs --no-verify-jwt
// Schedule: daily cron AFTER device-verified nudges (see docs/SCHEDULED_JOBS.md).

import { createClient } from "@supabase/supabase-js";
import {
  loadServiceAccount,
  sendPushToUserDevices,
} from "../_shared/fcm.ts";

interface TripInfo {
  name: string;
  lifecycle: string;
}

interface TripMemberRow {
  trip_id: string;
  user_id: string;
  close_notified_at?: string | null;
  close_reminded_at?: string | null;
  close_accepted_at?: string | null;
  close_objected_at?: string | null;
  settle_nudged_at?: string | null;
  trips: TripInfo | TripInfo[] | null;
}

function tripName(row: TripMemberRow): string {
  const trip = Array.isArray(row.trips) ? row.trips[0] : row.trips;
  return trip?.name ?? "your trip";
}

function tripRoute(tripId: string, suffix = ""): string {
  return `/trips/${tripId}${suffix}`;
}

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
  const serviceAccount = loadServiceAccount();
  const pushEnabled = serviceAccount != null;

  const pushStats = {
    close_notices: 0,
    day7_reminders: 0,
    deemed_closed_notices: 0,
    settle_nudges: 0,
    push_sent: 0,
    push_failed: 0,
    push_pruned: 0,
  };

  const now = Date.now();
  const sevenDaysMs = 7 * 24 * 60 * 60 * 1000;

  const { data: noticeRows, error: noticeErr } = await supabase
    .from("trip_members")
    .select(
      "trip_id, user_id, close_notified_at, trips!inner(name, lifecycle)",
    )
    .eq("status", "active")
    .is("close_notified_at", null)
    .eq("trips.lifecycle", "closing");

  if (noticeErr) {
    console.error("close notice query failed", noticeErr);
  } else if (noticeRows?.length && pushEnabled) {
    for (const row of noticeRows as TripMemberRow[]) {
      const name = tripName(row);
      const result = await sendPushToUserDevices(
        supabase,
        serviceAccount!,
        row.user_id,
        {
          title: "Trip is closing",
          body:
            `${name} — review balances. Auto-closes 14 days after you're notified.`,
          route: tripRoute(row.trip_id, "/close-report"),
        },
      );
      pushStats.push_sent += result.sent;
      pushStats.push_failed += result.failed;
      pushStats.push_pruned += result.pruned;

      if (result.sent > 0) {
        await supabase.rpc("_stamp_member_close_notified", {
          p_trip_id: row.trip_id,
          p_user_id: row.user_id,
        });
        pushStats.close_notices++;
      }
    }
  }

  const { data: remindRows, error: remindErr } = await supabase
    .from("trip_members")
    .select(
      "trip_id, user_id, close_notified_at, close_reminded_at, close_accepted_at, close_objected_at, trips!inner(name, lifecycle)",
    )
    .eq("status", "active")
    .not("close_notified_at", "is", null)
    .is("close_reminded_at", null)
    .is("close_accepted_at", null)
    .is("close_objected_at", null)
    .eq("trips.lifecycle", "closing");

  if (remindErr) {
    console.error("day7 query failed", remindErr);
  } else if (remindRows?.length && pushEnabled) {
    for (const row of remindRows as TripMemberRow[]) {
      const notifiedAt = Date.parse(row.close_notified_at ?? "");
      if (Number.isNaN(notifiedAt) || now < notifiedAt + sevenDaysMs) {
        continue;
      }

      if (pushEnabled) {
        const name = tripName(row);
        const result = await sendPushToUserDevices(
          supabase,
          serviceAccount!,
          row.user_id,
          {
            title: "7 days left",
            body: `7 days left to review ${name} before it closes.`,
            route: tripRoute(row.trip_id, "/close-report"),
          },
        );
        pushStats.push_sent += result.sent;
        pushStats.push_failed += result.failed;
        pushStats.push_pruned += result.pruned;
        if (result.sent === 0) continue;
      } else {
        continue;
      }

      await supabase.rpc("mark_close_reminder_sent", {
        p_trip_id: row.trip_id,
        p_user_id: row.user_id,
      });
      pushStats.day7_reminders++;
    }
  }

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

  if (pushEnabled) {
    const deemedCount = (jobResult as Record<string, number>)?.deemed_closed ?? 0;
    if (deemedCount > 0) {
      const { data: closedTrips } = await supabase
        .from("trips")
        .select("id, name")
        .eq("lifecycle", "closed")
        .gte("closed_at", new Date(now - 86_400_000).toISOString());

      for (const trip of closedTrips ?? []) {
        const { data: members } = await supabase
          .from("trip_members")
          .select("user_id")
          .eq("trip_id", trip.id)
          .eq("status", "active");

        for (const member of members ?? []) {
          const result = await sendPushToUserDevices(
            supabase,
            serviceAccount!,
            member.user_id as string,
            {
              title: "Trip closed",
              body: `${trip.name} closed. Settle up when ready.`,
              route: tripRoute(trip.id, "/close-report"),
            },
          );
          pushStats.push_sent += result.sent;
          pushStats.push_failed += result.failed;
          pushStats.deemed_closed_notices += result.sent > 0 ? 1 : 0;
        }
      }
    }

    const { data: nudgeMembers } = await supabase
      .from("trip_members")
      .select("trip_id, user_id, settle_nudged_at, trips!inner(name, lifecycle)")
      .eq("status", "active")
      .eq("trips.lifecycle", "closed")
      .not("settle_nudged_at", "is", null)
      .gte("settle_nudged_at", new Date(now - 86_400_000).toISOString());

    for (const row of (nudgeMembers ?? []) as TripMemberRow[]) {
      const name = tripName(row);
      const result = await sendPushToUserDevices(
        supabase,
        serviceAccount!,
        row.user_id,
        {
          title: "Balance to settle",
          body: `You still have a balance to settle in ${name}.`,
          route: tripRoute(row.trip_id),
        },
      );
      pushStats.push_sent += result.sent;
      pushStats.push_failed += result.failed;
      pushStats.settle_nudges += result.sent > 0 ? 1 : 0;
    }
  }

  const detail = { ...(jobResult as Record<string, unknown>), push: pushStats };

  const { data: heartbeatId, error: hbError } = await supabase.rpc(
    "record_job_heartbeat",
    {
      p_job_name: "trip-lifecycle-jobs",
      p_detail: JSON.stringify(detail),
    },
  );
  if (hbError) {
    console.error("heartbeat failed", hbError);
  }

  return new Response(
    JSON.stringify({ ok: true, result: detail, heartbeatId }),
    { headers: { "Content-Type": "application/json" } },
  );
});
