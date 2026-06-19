/** Pure helpers for S48 end-date soft-close sweep (testable without Supabase). */

export interface SoftCloseTripRow {
  lifecycle: string;
  end_date: string | null;
  reopened_at?: string | null;
  id?: string;
  name?: string;
  owner_id?: string;
}

/** Matches edge-fn query: active, end_date set and passed, never reopened. */
export function isSoftCloseEligible(
  trip: SoftCloseTripRow,
  todayIso: string,
): boolean {
  if (trip.lifecycle !== "active") return false;
  if (trip.reopened_at != null) return false;
  const endDate = trip.end_date;
  if (endDate == null || endDate === "") return false;
  return endDate <= todayIso;
}

/** Recent wrap window: end_date within the last two calendar days (inclusive). */
export function shouldNotifyWrappedTrip(
  endDate: string,
  todayIso: string,
): boolean {
  const today = parseIsoDate(todayIso);
  const end = parseIsoDate(endDate);
  const twoDaysAgo = new Date(today);
  twoDaysAgo.setUTCDate(twoDaysAgo.getUTCDate() - 2);
  return end >= twoDaysAgo;
}

export function todayIsoUtc(now = new Date()): string {
  return now.toISOString().slice(0, 10);
}

function parseIsoDate(iso: string): Date {
  const [y, m, d] = iso.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d));
}
