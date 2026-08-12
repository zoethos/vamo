export interface IdentityIntegritySummary {
  duplicate_verified_email_groups: number;
  duplicate_verified_email_accounts: number;
  duplicate_profile_groups: number;
  duplicate_profile_accounts: number;
  apple_private_relay_only_accounts: number;
}

const attentionCounterNames = [
  "duplicate_verified_email_groups",
  "duplicate_profile_groups",
  "apple_private_relay_only_accounts",
] as const;

type AttentionCounterName = (typeof attentionCounterNames)[number];

/**
 * Preserves the aggregate detector result while making a non-zero exposure
 * visible in the lifecycle heartbeat. Counter names contain no identity data.
 */
export function identityIntegrityHeartbeat(
  summary: IdentityIntegritySummary,
) {
  const attentionCounters = attentionCounterNames.filter(
    (counter): counter is AttentionCounterName => summary[counter] > 0,
  );

  return {
    status: attentionCounters.length > 0 ? "attention" : "ok",
    ...(attentionCounters.length > 0
      ? { attention_counters: attentionCounters }
      : {}),
    ...summary,
  };
}
