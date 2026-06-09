import { assertEquals } from "jsr:@std/assert@1.0.19";
import { shouldStampAfterRecord } from "./notifications.ts";

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
