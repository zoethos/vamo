import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  type DraftInput,
  parseDraftInput,
  validateRouteDraft,
} from "./draft.ts";

const TRIP = "11111111-1111-4111-8111-111111111111";

function baseBody(overrides: Record<string, unknown> = {}) {
  return {
    trip_id: TRIP,
    destination: "Amalfi Coast",
    trip_start: "2026-07-01",
    trip_end: "2026-07-07",
    legs: [
      {
        mode: "car",
        window_start: "2026-07-01",
        window_end: "2026-07-03",
        reach_type: "distance",
        reach_value: 600,
      },
      { mode: "train", reach_type: "time", reach_value: 5 },
    ],
    ...overrides,
  };
}

Deno.test("parseDraftInput accepts a valid envelope", () => {
  const result = parseDraftInput(baseBody());
  assert("input" in result);
  const input = result.input;
  assertEquals(input.legs.length, 2);
  assertEquals(input.legs[0].reachValueKm, 600);
  assertEquals(input.legs[1].reachType, "time");
  // Open-ended leg windows parse to null.
  assertEquals(input.legs[1].windowStart, null);
});

Deno.test("parseDraftInput rejects bad input", () => {
  assertEquals(parseDraftInput({ ...baseBody(), trip_id: "nope" }), {
    error: "invalid_trip_id",
  });
  assertEquals(parseDraftInput({ ...baseBody(), legs: [] }), {
    error: "no_legs",
  });
  assertEquals(
    parseDraftInput({ ...baseBody(), legs: [{ mode: "rocket" }] }),
    { error: "invalid_leg_mode" },
  );
  assertEquals(
    parseDraftInput({
      ...baseBody(),
      trip_start: "2026-07-07",
      trip_end: "2026-07-01",
    }),
    { error: "trip_end_before_start" },
  );
});

const INPUT: DraftInput = (() => {
  const r = parseDraftInput(baseBody());
  if (!("input" in r)) throw new Error("setup");
  return r.input;
})();

Deno.test("validateRouteDraft accepts an in-bounds draft", () => {
  const result = validateRouteDraft({
    plan_items: [
      {
        kind: "transfer",
        title: "Drive to Positano",
        starts_at: "2026-07-01",
        ends_at: "2026-07-01",
        transfer_subtype: "drive",
        leg_index: 0,
        notes: null,
      },
      {
        kind: "train",
        title: "Train to Naples",
        starts_at: "2026-07-04",
        ends_at: "2026-07-04",
        transfer_subtype: null,
        leg_index: 1,
        notes: "Regionale",
      },
    ],
    warnings: [],
    unresolved_questions: ["Hotel in Positano or Amalfi town?"],
  }, INPUT);
  assert(result.ok);
  assertEquals(result.draft.plan_items.length, 2);
  assertEquals(result.draft.unresolved_questions.length, 1);
});

Deno.test("validateRouteDraft hard-fails bad kind, dates, range", () => {
  const bad = (items: unknown) =>
    validateRouteDraft(
      { plan_items: items, warnings: [], unresolved_questions: [] },
      INPUT,
    );

  assertEquals(bad([]).hardError, "empty_plan_items");
  assertEquals(
    bad([{ kind: "spaceship", title: "x" }]).hardError,
    "bad_kind",
  );
  assertEquals(
    bad([{
      kind: "visit",
      title: "x",
      starts_at: "2026-07-05",
      ends_at: "2026-07-04",
    }])
      .hardError,
    "end_before_start",
  );
  // Outside the trip window (trip ends 07-07).
  assertEquals(
    bad([{ kind: "visit", title: "x", starts_at: "2026-07-09" }]).hardError,
    "outside_trip_range",
  );
  assertEquals(
    bad([{ kind: "visit", title: "x", leg_index: 9 }]).hardError,
    "bad_leg_index",
  );
});

Deno.test("validateRouteDraft warns (not fails) on soft mismatches", () => {
  const result = validateRouteDraft({
    plan_items: [
      {
        // Leg 0 window is 07-01..07-03; this starts after it → warning.
        kind: "visit",
        title: "Late visit",
        starts_at: "2026-07-03",
        ends_at: "2026-07-05",
        // subtype on a non-transfer → dropped.
        transfer_subtype: "drive",
        leg_index: 0,
        notes: null,
      },
    ],
    warnings: ["model note"],
    unresolved_questions: [],
  }, INPUT);
  assert(result.ok);
  assertEquals(result.draft.plan_items[0].transfer_subtype, null);
  assert(result.draft.warnings.length >= 2); // model note + leg-window warning
});
