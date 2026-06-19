// Daily trip lifecycle jobs — S17/S22/S46/S48 (record-first notices; push best-effort).
// Deploy: supabase functions deploy trip-lifecycle-jobs --no-verify-jwt
// Schedule: daily cron AFTER device-verified nudges (see docs/SCHEDULED_JOBS.md).

import { createClient } from "@supabase/supabase-js";
import { loadServiceAccount, sendPushToUserDevices } from "../_shared/fcm.ts";
import {
  recordNotification,
  shouldStampAfterRecord,
} from "../_shared/notifications.ts";
import {
  isSoftCloseEligible,
  shouldNotifyWrappedTrip,
  todayIsoUtc,
  type SoftCloseTripRow,
} from "../_shared/soft_close_sweep.ts";

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

  const recordStats = {
    close_notices_recorded: 0,
    day7_reminders_recorded: 0,
    deemed_closed_notices_recorded: 0,
    settle_nudges_recorded: 0,
    wrapped_trip_notices_recorded: 0,
  };

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
    .eq("trips.lifecycle", "closing");

  if (noticeErr) {
    console.error("close notice query failed", noticeErr);
  } else if (noticeRows?.length) {
    for (const row of noticeRows as TripMemberRow[]) {
      const name = tripName(row);
      const route = tripRoute(row.trip_id, "/close-report");
      const title = "Trip is closing";
      const body =
        `${name} — review balances. Auto-closes 14 days after you're notified.`;

      const recordId = await recordNotification(supabase, {
        userId: row.user_id,
        tripId: row.trip_id,
        type: "close_notice",
        title,
        body,
        route,
      });
      const recorded = shouldStampAfterRecord(recordId);
      if (recorded) {
        recordStats.close_notices_recorded++;
        await supabase.rpc("_stamp_member_close_notified", {
          p_trip_id: row.trip_id,
          p_user_id: row.user_id,
        });
      } else if (row.close_notified_at == null) {
        const { data: existingNotice, error: existingNoticeErr } =
          await supabase
            .from("notifications")
            .select("id")
            .eq("user_id", row.user_id)
            .eq("trip_id", row.trip_id)
            .eq("type", "close_notice")
            .maybeSingle();
        if (existingNoticeErr) {
          console.error("close notice lookup failed", existingNoticeErr);
        } else if (existingNotice?.id) {
          await supabase.rpc("_stamp_member_close_notified", {
            p_trip_id: row.trip_id,
            p_user_id: row.user_id,
          });
        }
      }

      if (recorded && pushEnabled) {
        const result = await sendPushToUserDevices(
          supabase,
          serviceAccount!,
          row.user_id,
          { title, body, route },
        );
        pushStats.push_sent += result.sent;
        pushStats.push_failed += result.failed;
        pushStats.push_pruned += result.pruned;
        if (result.sent > 0) {
          pushStats.close_notices++;
        }
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
  } else if (remindRows?.length) {
    for (const row of remindRows as TripMemberRow[]) {
      const notifiedAt = Date.parse(row.close_notified_at ?? "");
      if (Number.isNaN(notifiedAt) || now < notifiedAt + sevenDaysMs) {
        continue;
      }

      const name = tripName(row);
      const route = tripRoute(row.trip_id, "/close-report");
      const title = "7 days left";
      const body = `7 days left to review ${name} before it closes.`;

      const recordId = await recordNotification(supabase, {
        userId: row.user_id,
        tripId: row.trip_id,
        type: "close_reminder",
        title,
        body,
        route,
      });
      if (shouldStampAfterRecord(recordId)) {
        recordStats.day7_reminders_recorded++;
        await supabase.rpc("mark_close_reminder_sent", {
          p_trip_id: row.trip_id,
          p_user_id: row.user_id,
        });
      }

      if (pushEnabled) {
        const result = await sendPushToUserDevices(
          supabase,
          serviceAccount!,
          row.user_id,
          { title, body, route },
        );
        pushStats.push_sent += result.sent;
        pushStats.push_failed += result.failed;
        pushStats.push_pruned += result.pruned;
        if (result.sent > 0) {
          pushStats.day7_reminders++;
        }
      }
    }
  }

  const softCloseStats = {
    soft_closed: 0,
    wrapped_notices_recorded: 0,
  };

  const todayIso = todayIsoUtc(new Date(now));

  const { data: softCloseRows, error: softCloseErr } = await supabase
    .from("trips")
    .select("id, name, owner_id, end_date, reopened_at, lifecycle")
    .eq("lifecycle", "active")
    .not("end_date", "is", null)
    .lte("end_date", todayIso)
    .is("reopened_at", null);

  if (softCloseErr) {
    console.error("soft close query failed", softCloseErr);
  } else if (softCloseRows?.length) {
    for (const raw of softCloseRows) {
      const row = raw as SoftCloseTripRow & {
        id: string;
        name: string;
        owner_id: string;
        end_date: string;
      };
      if (!isSoftCloseEligible(row, todayIso)) continue;

      if (shouldNotifyWrappedTrip(row.end_date, todayIso)) {
        const route = tripRoute(row.id);
        const title = "Your trip wrapped";
        const body = `Your ${row.name} wrapped — relive it?`;
        const recordId = await recordNotification(supabase, {
          userId: row.owner_id,
          tripId: row.id,
          type: "wrapped_trip",
          title,
          body,
          route,
        });
        if (shouldStampAfterRecord(recordId)) {
          recordStats.wrapped_trip_notices_recorded++;
          softCloseStats.wrapped_notices_recorded++;
        }
      }

      const { error: enterErr } = await supabase.rpc("_enter_soft_close", {
        p_trip_id: row.id,
      });
      if (enterErr) {
        console.error("_enter_soft_close failed", row.id, enterErr);
      } else {
        softCloseStats.soft_closed++;
      }
    }
  }

  const { data: jobResult, error: jobError } = await supabase.rpc(
    "run_trip_lifecycle_jobs",
  );
  if (jobError) {
    console.error("run_trip_lifecycle_jobs failed", jobError);
    return new Response(
      JSON.stringify({ ok: false, error: jobError.message }),
      {
        status: 500,
        headers: { "Content-Type": "application/json" },
      },
    );
  }

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
        const userId = member.user_id as string;
        const route = tripRoute(trip.id, "/close-report");
        const title = "Trip closed";
        const body = `${trip.name} closed. Settle up when ready.`;

        const recordId = await recordNotification(supabase, {
          userId,
          tripId: trip.id,
          type: "deemed_closed",
          title,
          body,
          route,
        });
        if (shouldStampAfterRecord(recordId)) {
          recordStats.deemed_closed_notices_recorded++;
        }

        if (pushEnabled) {
          const result = await sendPushToUserDevices(
            supabase,
            serviceAccount!,
            userId,
            { title, body, route },
          );
          pushStats.push_sent += result.sent;
          pushStats.push_failed += result.failed;
          pushStats.push_pruned += result.pruned;
          if (result.sent > 0) {
            pushStats.deemed_closed_notices++;
          }
        }
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
    const route = tripRoute(row.trip_id);
    const title = "Balance to settle";
    const body = `You still have a balance to settle in ${name}.`;

    const recordId = await recordNotification(supabase, {
      userId: row.user_id,
      tripId: row.trip_id,
      type: "settle_nudge",
      title,
      body,
      route,
    });
    if (shouldStampAfterRecord(recordId)) {
      recordStats.settle_nudges_recorded++;
    }

    if (pushEnabled) {
      const result = await sendPushToUserDevices(
        supabase,
        serviceAccount!,
        row.user_id,
        { title, body, route },
      );
      pushStats.push_sent += result.sent;
      pushStats.push_failed += result.failed;
      pushStats.push_pruned += result.pruned;
      if (result.sent > 0) {
        pushStats.settle_nudges++;
      }
    }
  }

  const detail = {
    ...(jobResult as Record<string, unknown>),
    soft_close: softCloseStats,
    recorded: recordStats,
    push: pushStats,
  };

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
