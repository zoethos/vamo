import { assertEquals } from "jsr:@std/assert@1.0.19";
import { identityIntegrityHeartbeat } from "./identity_integrity.ts";

const cleanSummary = {
  duplicate_verified_email_groups: 0,
  duplicate_verified_email_accounts: 0,
  duplicate_profile_groups: 0,
  duplicate_profile_accounts: 0,
  apple_private_relay_only_accounts: 0,
};

Deno.test("identity integrity heartbeat is ok when no exposure counters trip", () => {
  assertEquals(identityIntegrityHeartbeat(cleanSummary), {
    status: "ok",
    ...cleanSummary,
  });
});

Deno.test("identity integrity heartbeat escalates aggregate duplicate and relay counters", () => {
  assertEquals(
    identityIntegrityHeartbeat({
      ...cleanSummary,
      duplicate_verified_email_groups: 2,
      duplicate_verified_email_accounts: 4,
      duplicate_profile_groups: 1,
      duplicate_profile_accounts: 2,
      apple_private_relay_only_accounts: 3,
    }),
    {
      status: "attention",
      attention_counters: [
        "duplicate_verified_email_groups",
        "duplicate_profile_groups",
        "apple_private_relay_only_accounts",
      ],
      duplicate_verified_email_groups: 2,
      duplicate_verified_email_accounts: 4,
      duplicate_profile_groups: 1,
      duplicate_profile_accounts: 2,
      apple_private_relay_only_accounts: 3,
    },
  );
});
