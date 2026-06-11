import { assertEquals } from "jsr:@std/assert@1.0.19";
import { recordNotification, shouldStampAfterRecord } from "./notifications.ts";

Deno.test("shouldStampAfterRecord is true when notice recorded", () => {
  assertEquals(shouldStampAfterRecord("uuid-1"), true);
});

Deno.test("shouldStampAfterRecord is false when record failed", () => {
  assertEquals(shouldStampAfterRecord(null), false);
});

Deno.test("close_notified stamp decoupled from push — record succeeds, sent zero", () => {
  const recordId = "notice-id";
  const pushSent = 0;
  assertEquals(shouldStampAfterRecord(recordId), true);
  assertEquals(pushSent, 0);
});

Deno.test("suppressed duplicate (0033 on-conflict) yields null and is not counted", async () => {
  // record_notification returns null data with no error when the settle-nudge
  // partial unique index suppresses a duplicate insert.
  const dedupingClient = {
    rpc: () => Promise.resolve({ data: null, error: null }),
  };
  const recordId = await recordNotification(dedupingClient, {
    userId: "user-1",
    tripId: "trip-1",
    type: "settle_nudge",
    title: "Balance to settle",
    body: "You still have a balance to settle in Amalfi.",
    route: "/trips/trip-1",
  });
  assertEquals(recordId, null);
  assertEquals(shouldStampAfterRecord(recordId), false);
});
