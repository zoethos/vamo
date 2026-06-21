import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

export interface UsageReservation {
  reserved: boolean;
  gated?: boolean;
  reason?: string;
  reservationId?: string;
  provider?: string;
  cacheTtlSeconds?: number;
  canCacheContent?: boolean;
  config?: Record<string, unknown>;
}

interface ReservationPayload {
  reserved?: boolean;
  gated?: boolean;
  reason?: string;
  reservation_id?: string;
  provider?: string;
  cache_ttl_seconds?: number;
  can_cache_content?: boolean;
  config?: Record<string, unknown>;
}

export async function reserveServiceUsage(
  supabase: SupabaseClient,
  args: {
    idempotencyKey: string;
    service: string;
    userId: string;
  },
): Promise<UsageReservation> {
  const { data, error } = await supabase.rpc("reserve_service_usage", {
    p_idempotency_key: args.idempotencyKey,
    p_service: args.service,
    p_user_id: args.userId,
  });
  if (error) throw error;
  const payload = (data ?? {}) as ReservationPayload;
  return {
    reserved: payload.reserved === true,
    gated: payload.gated === true,
    reason: payload.reason,
    reservationId: payload.reservation_id,
    provider: payload.provider,
    cacheTtlSeconds: payload.cache_ttl_seconds,
    canCacheContent: payload.can_cache_content === true,
    config: payload.config,
  };
}

export async function completeServiceUsageReservation(
  supabase: SupabaseClient,
  reservationId: string | undefined,
): Promise<void> {
  if (!reservationId) return;
  const { error } = await supabase.rpc(
    "complete_service_usage_reservation",
    { p_reservation_id: reservationId },
  );
  if (error) throw error;
}

export async function releaseServiceUsageReservation(
  supabase: SupabaseClient,
  reservationId: string | undefined,
  status: "failed" | "released" = "failed",
): Promise<void> {
  if (!reservationId) return;
  const { error } = await supabase.rpc(
    "release_service_usage_reservation",
    { p_reservation_id: reservationId, p_status: status },
  );
  if (error) throw error;
}

export async function recordPremiumGateNotification(
  supabase: SupabaseClient,
  args: { userId: string; service: string; reason: string },
): Promise<void> {
  await supabase.rpc("record_premium_gate_notification", {
    p_user_id: args.userId,
    p_service: args.service,
    p_reason: args.reason,
  });
}
