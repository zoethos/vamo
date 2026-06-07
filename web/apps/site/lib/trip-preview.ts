import { cache } from "react";

import { getSupabaseAnonClient } from "./supabase";
import { defaultThemePack, parseThemePack, type SnapshotThemePack } from "./theme";

export type TripPreview = {
  tripName: string;
  destination: string | null;
  startDate: string | null;
  endDate: string | null;
  memberCount: number;
  theme: SnapshotThemePack;
};

type RpcPreview = {
  trip_name?: unknown;
  destination?: unknown;
  start_date?: unknown;
  end_date?: unknown;
  member_count?: unknown;
  theme?: unknown;
};

function asNullableString(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

function parsePreview(raw: RpcPreview): TripPreview | null {
  if (typeof raw.trip_name !== "string" || raw.trip_name.length === 0) {
    return null;
  }
  const memberCount =
    typeof raw.member_count === "number"
      ? raw.member_count
      : Number(raw.member_count);
  if (!Number.isFinite(memberCount) || memberCount < 0) {
    return null;
  }
  return {
    tripName: raw.trip_name,
    destination: asNullableString(raw.destination),
    startDate: asNullableString(raw.start_date),
    endDate: asNullableString(raw.end_date),
    memberCount,
    theme: parseThemePack(raw.theme ?? defaultThemePack),
  };
}

export const fetchTripPreview = cache(
  async (token: string): Promise<TripPreview | null> => {
    const client = getSupabaseAnonClient();
    if (!client) return null;
    try {
      const { data, error } = await client.rpc("get_trip_preview", {
        p_token: token,
      });
      if (error || data == null) return null;
      return parsePreview(data as RpcPreview);
    } catch {
      return null;
    }
  },
);

export function formatTripDates(
  startDate: string | null,
  endDate: string | null,
): string | null {
  if (!startDate && !endDate) return null;
  const fmt = new Intl.DateTimeFormat("en", {
    month: "short",
    day: "numeric",
    year: "numeric",
  });
  if (startDate && endDate && startDate !== endDate) {
    return `${fmt.format(new Date(startDate))} – ${fmt.format(new Date(endDate))}`;
  }
  const single = startDate ?? endDate;
  return single ? fmt.format(new Date(single)) : null;
}

export function memberCountLabel(count: number): string {
  return count === 1 ? "1 Vamigo going" : `${count} Vamigos going`;
}
