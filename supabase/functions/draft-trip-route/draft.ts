// Pure, provider-agnostic core for draft-trip-route: input parsing, the strict
// JSON schema sent to the model, and deterministic validation of the model's
// proposal. No Deno/network access here so it stays unit-testable.

export const TRAVEL_MODES = [
  "car",
  "motorbike",
  "bike",
  "train",
  "flight",
  "bus",
] as const;
export type TravelMode = (typeof TRAVEL_MODES)[number];

export const PLAN_KINDS = [
  "lodging",
  "flight",
  "train",
  "activity",
  "visit",
  "transfer",
  "other",
] as const;
export type PlanKind = (typeof PLAN_KINDS)[number];

export const TRANSFER_SUBTYPES = [
  "car_rental",
  "train",
  "transit",
  "drive",
  "flight",
] as const;

export type ReachType = "distance" | "time";

export interface LegInput {
  mode: TravelMode;
  windowStart: string | null; // YYYY-MM-DD
  windowEnd: string | null;
  reachType: ReachType;
  reachValueKm: number | null; // canonical km (distance) or hours/day (time); null = no limit
}

export interface DraftInput {
  tripId: string;
  destination: string;
  tripStart: string | null;
  tripEnd: string | null;
  legs: LegInput[];
}

export interface PlanItemDraft {
  kind: PlanKind;
  title: string;
  starts_at: string | null;
  ends_at: string | null;
  transfer_subtype: string | null;
  leg_index: number | null;
  notes: string | null;
}

export interface RouteDraft {
  plan_items: PlanItemDraft[];
  warnings: string[];
  unresolved_questions: string[];
}

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const MAX_LEGS = 12;
const MAX_PLAN_ITEMS = 60;

export function parseDate(value: unknown): string | null {
  if (typeof value !== "string" || !DATE_RE.test(value)) return null;
  const t = Date.parse(`${value}T00:00:00Z`);
  return Number.isNaN(t) ? null : value;
}

/** Parse + validate the client request. Returns the input or an error code. */
export function parseDraftInput(
  payload: unknown,
): { input: DraftInput } | { error: string } {
  if (!payload || typeof payload !== "object") return { error: "invalid_json" };
  const p = payload as Record<string, unknown>;

  const tripId = typeof p.trip_id === "string" ? p.trip_id : "";
  if (!UUID_RE.test(tripId)) return { error: "invalid_trip_id" };

  const destination = (typeof p.destination === "string" ? p.destination : "")
    .trim();
  if (destination.length < 2 || destination.length > 80) {
    return { error: "invalid_destination" };
  }

  const tripStart = parseDate(p.trip_start);
  const tripEnd = parseDate(p.trip_end);
  if (tripStart && tripEnd && tripEnd < tripStart) {
    return { error: "trip_end_before_start" };
  }

  if (!Array.isArray(p.legs) || p.legs.length === 0) {
    return { error: "no_legs" };
  }
  if (p.legs.length > MAX_LEGS) return { error: "too_many_legs" };

  const legs: LegInput[] = [];
  for (const raw of p.legs) {
    if (!raw || typeof raw !== "object") return { error: "invalid_leg" };
    const l = raw as Record<string, unknown>;
    const mode = l.mode;
    if (
      typeof mode !== "string" || !TRAVEL_MODES.includes(mode as TravelMode)
    ) {
      return { error: "invalid_leg_mode" };
    }
    const reachType = l.reach_type === "time" ? "time" : "distance";
    const reachValueKm = typeof l.reach_value === "number" &&
        Number.isFinite(l.reach_value) && l.reach_value > 0
      ? l.reach_value
      : null;
    legs.push({
      mode: mode as TravelMode,
      windowStart: parseDate(l.window_start),
      windowEnd: parseDate(l.window_end),
      reachType,
      reachValueKm,
    });
  }

  return {
    input: { tripId, destination, tripStart, tripEnd, legs },
  };
}

/** Strict JSON schema the model must satisfy (OpenAI structured outputs). */
export const ROUTE_JSON_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["plan_items", "warnings", "unresolved_questions"],
  properties: {
    plan_items: {
      type: "array",
      maxItems: MAX_PLAN_ITEMS,
      items: {
        type: "object",
        additionalProperties: false,
        required: [
          "kind",
          "title",
          "starts_at",
          "ends_at",
          "transfer_subtype",
          "leg_index",
          "notes",
        ],
        properties: {
          kind: { type: "string", enum: [...PLAN_KINDS] },
          title: { type: "string", minLength: 1, maxLength: 80 },
          starts_at: {
            type: ["string", "null"],
            description: "YYYY-MM-DD within the trip window.",
          },
          ends_at: { type: ["string", "null"] },
          transfer_subtype: {
            type: ["string", "null"],
            enum: [...TRANSFER_SUBTYPES, null],
          },
          leg_index: { type: ["integer", "null"] },
          notes: { type: ["string", "null"], maxLength: 200 },
        },
      },
    },
    warnings: {
      type: "array",
      items: { type: "string", maxLength: 200 },
    },
    unresolved_questions: {
      type: "array",
      items: { type: "string", maxLength: 200 },
    },
  },
};

export interface ValidationResult {
  ok: boolean;
  hardError: string | null;
  draft: RouteDraft;
}

/**
 * Deterministic, AI-free validation of the model's proposal. Hard errors
 * (returned as `invalid_output`) reject the draft; softer mismatches (an item
 * outside its leg window, a stray transfer subtype) are appended to `warnings`
 * so the user still sees a usable draft. Feasibility is code-owned here — the
 * model proposes, this validates.
 */
export function validateRouteDraft(
  raw: unknown,
  input: DraftInput,
): ValidationResult {
  const empty: RouteDraft = {
    plan_items: [],
    warnings: [],
    unresolved_questions: [],
  };
  if (!raw || typeof raw !== "object") {
    return { ok: false, hardError: "not_object", draft: empty };
  }
  const r = raw as Record<string, unknown>;
  if (!Array.isArray(r.plan_items)) {
    return { ok: false, hardError: "missing_plan_items", draft: empty };
  }
  if (r.plan_items.length === 0) {
    return { ok: false, hardError: "empty_plan_items", draft: empty };
  }
  if (r.plan_items.length > MAX_PLAN_ITEMS) {
    return { ok: false, hardError: "too_many_plan_items", draft: empty };
  }

  const warnings = stringArray(r.warnings);
  const items: PlanItemDraft[] = [];

  for (const rawItem of r.plan_items) {
    if (!rawItem || typeof rawItem !== "object") {
      return { ok: false, hardError: "bad_item", draft: empty };
    }
    const it = rawItem as Record<string, unknown>;

    const kind = it.kind;
    if (typeof kind !== "string" || !PLAN_KINDS.includes(kind as PlanKind)) {
      return { ok: false, hardError: "bad_kind", draft: empty };
    }
    const title = typeof it.title === "string" ? it.title.trim() : "";
    if (title.length < 1 || title.length > 80) {
      return { ok: false, hardError: "bad_title", draft: empty };
    }

    const startsAt = parseDate(it.starts_at);
    const endsAt = parseDate(it.ends_at);
    if (it.starts_at != null && startsAt === null) {
      return { ok: false, hardError: "bad_date", draft: empty };
    }
    if (it.ends_at != null && endsAt === null) {
      return { ok: false, hardError: "bad_date", draft: empty };
    }
    if (startsAt && endsAt && endsAt < startsAt) {
      return { ok: false, hardError: "end_before_start", draft: empty };
    }
    // Hard: any dated endpoint outside the trip window.
    const outsideTrip = (d: string | null) =>
      d !== null &&
      ((input.tripStart !== null && d < input.tripStart) ||
        (input.tripEnd !== null && d > input.tripEnd));
    if (outsideTrip(startsAt) || outsideTrip(endsAt)) {
      return { ok: false, hardError: "outside_trip_range", draft: empty };
    }

    let legIndex: number | null = null;
    if (typeof it.leg_index === "number" && Number.isInteger(it.leg_index)) {
      if (it.leg_index < 0 || it.leg_index >= input.legs.length) {
        return { ok: false, hardError: "bad_leg_index", draft: empty };
      }
      legIndex = it.leg_index;
      // Soft: item should sit inside the referenced leg's window.
      const leg = input.legs[legIndex];
      if (startsAt && leg.windowStart && startsAt < leg.windowStart) {
        warnings.push(`Item "${title}" starts before its leg window.`);
      }
      if (endsAt && leg.windowEnd && endsAt > leg.windowEnd) {
        warnings.push(`Item "${title}" ends after its leg window.`);
      }
    }

    let subtype = typeof it.transfer_subtype === "string"
      ? it.transfer_subtype
      : null;
    if (subtype && !TRANSFER_SUBTYPES.includes(subtype as never)) {
      subtype = null;
    }
    if (subtype && kind !== "transfer") {
      // Soft: subtype only meaningful for transfers.
      subtype = null;
    }

    items.push({
      kind: kind as PlanKind,
      title,
      starts_at: startsAt,
      ends_at: endsAt,
      transfer_subtype: subtype,
      leg_index: legIndex,
      notes: typeof it.notes === "string" && it.notes.trim().length > 0
        ? it.notes.trim().slice(0, 200)
        : null,
    });
  }

  return {
    ok: true,
    hardError: null,
    draft: {
      plan_items: items,
      warnings,
      unresolved_questions: stringArray(r.unresolved_questions),
    },
  };
}

function stringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .filter((v): v is string => typeof v === "string" && v.trim().length > 0)
    .map((v) => v.trim().slice(0, 200))
    .slice(0, 20);
}
