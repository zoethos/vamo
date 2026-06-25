// Slice 5 — CI-safe eval fixtures for the deterministic draft layer.
//
// Each scenario is an envelope (request body) and, for output cases, a canned
// model proposal. NO live OpenAI / routing / paid calls — these run the pure
// `parseDraftInput` + `validateRouteDraft` (incl. straight-line feasibility) and
// assert the expected shape/warnings. This is the safety net that locks current
// behaviour before a real routing provider (Slice 4.1) is introduced.

import {
  assert,
  assertEquals,
} from "jsr:@std/assert@1.0.19";
import { parseDraftInput, validateRouteDraft } from "./draft.ts";

const TRIP = "11111111-1111-4111-8111-111111111111";

const ROME = { lat: 41.9, lng: 12.5 };
const NAPLES = { lat: 40.85, lng: 14.25 }; // ~190 km from Rome
const PARIS = { lat: 48.85, lng: 2.35 }; // ~1100 km from Rome
const FAR = { lat: 42.0, lng: 13.5 }; // ~124 km from {42,12}
const NEAR = { lat: 42.0, lng: 12.0 };

type Json = Record<string, unknown>;

function body(over: Json = {}): Json {
  return {
    trip_id: TRIP,
    destination: "Amalfi Coast",
    trip_start: "2026-07-01",
    trip_end: "2026-07-07",
    legs: [{ mode: "car", reach_type: "distance", reach_value: 600 }],
    ...over,
  };
}

function item(over: Json): Json {
  return {
    kind: "transfer",
    title: "Hop",
    starts_at: null,
    ends_at: null,
    transfer_subtype: null,
    leg_index: null,
    notes: null,
    from: null,
    to: null,
    ...over,
  };
}

function output(items: Json[], over: Json = {}): Json {
  return { plan_items: items, warnings: [], unresolved_questions: [], ...over };
}

interface Scenario {
  name: string;
  body: Json;
  output?: unknown;
  expect: {
    parseError?: string;
    hardError?: string | null;
    itemCount?: number;
    warningIncludes?: string[];
    noKmCapWarning?: boolean;
  };
}

const SCENARIOS: Scenario[] = [
  {
    name: "amalfi car+train happy path — clean draft, no feasibility flags",
    body: body({
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
    }),
    output: output([
      item({
        title: "Drive to Naples",
        transfer_subtype: "drive",
        leg_index: 0,
        starts_at: "2026-07-01",
        ends_at: "2026-07-01",
        from: ROME,
        to: NAPLES,
      }),
      item({
        kind: "train",
        title: "Train onward",
        leg_index: 1,
        starts_at: "2026-07-04",
        ends_at: "2026-07-04",
      }),
    ]),
    expect: { hardError: null, itemCount: 2, noKmCapWarning: true },
  },
  {
    name: "impossible bike range — straight-line exceeds the 80 km cap",
    body: body({
      legs: [{ mode: "bike", reach_type: "distance", reach_value: 80 }],
    }),
    output: output([
      item({
        title: "Long ride",
        leg_index: 0,
        transfer_subtype: "transit",
        from: NEAR,
        to: FAR,
      }),
    ]),
    expect: {
      hardError: null,
      warningIncludes: ["exceeds your 80 km cap"],
    },
  },
  {
    name: "flight leg uncapped — far hop raises no distance flag",
    body: body({ legs: [{ mode: "flight", reach_type: "distance" }] }),
    output: output([
      item({
        kind: "flight",
        title: "Fly out",
        leg_index: 0,
        from: ROME,
        to: PARIS,
      }),
    ]),
    expect: { hardError: null, noKmCapWarning: true },
  },
  {
    name: "no trip dates — dated items are accepted",
    body: body({ trip_start: undefined, trip_end: undefined }),
    output: output([
      item({
        kind: "visit",
        title: "Wander",
        starts_at: "2026-09-01",
        ends_at: "2026-09-02",
      }),
    ]),
    expect: { hardError: null, itemCount: 1 },
  },
  {
    name: "multi-day window — item past its leg window warns (soft)",
    body: body({
      legs: [
        {
          mode: "car",
          window_start: "2026-07-01",
          window_end: "2026-07-03",
          reach_type: "distance",
          reach_value: 600,
        },
      ],
    }),
    output: output([
      item({
        kind: "visit",
        title: "Late visit",
        leg_index: 0,
        starts_at: "2026-07-02",
        ends_at: "2026-07-05",
      }),
    ]),
    expect: { hardError: null, warningIncludes: ["ends after its leg window"] },
  },
  {
    name: "outside trip range — hard reject",
    body: body(),
    output: output([
      item({ kind: "visit", title: "Too late", starts_at: "2026-07-09" }),
    ]),
    expect: { hardError: "outside_trip_range" },
  },
  {
    name: "empty proposal — hard reject",
    body: body(),
    output: output([]),
    expect: { hardError: "empty_plan_items" },
  },
  {
    name: "envelope with no legs — rejected at parse",
    body: body({ legs: [] }),
    expect: { parseError: "no_legs" },
  },
  {
    name: "envelope with an unknown mode — rejected at parse",
    body: body({ legs: [{ mode: "teleport", reach_type: "distance" }] }),
    expect: { parseError: "invalid_leg_mode" },
  },
];

for (const scenario of SCENARIOS) {
  Deno.test(`eval: ${scenario.name}`, () => {
    const parsed = parseDraftInput(scenario.body);

    if (scenario.expect.parseError) {
      assertEquals(parsed, { error: scenario.expect.parseError });
      return;
    }
    assert("input" in parsed, `${scenario.name}: expected a valid envelope`);
    if (scenario.output === undefined) return;

    const result = validateRouteDraft(scenario.output, parsed.input);

    if (scenario.expect.hardError !== undefined) {
      assertEquals(result.hardError, scenario.expect.hardError);
      if (scenario.expect.hardError) return; // rejected — nothing more to check
    }
    assert(result.ok, `${scenario.name}: expected a usable draft`);

    if (scenario.expect.itemCount !== undefined) {
      assertEquals(result.draft.plan_items.length, scenario.expect.itemCount);
    }
    for (const needle of scenario.expect.warningIncludes ?? []) {
      assert(
        result.draft.warnings.some((w) => w.includes(needle)),
        `${scenario.name}: expected a warning containing "${needle}", got ` +
          JSON.stringify(result.draft.warnings),
      );
    }
    if (scenario.expect.noKmCapWarning) {
      assert(
        !result.draft.warnings.some((w) => w.includes("km cap")),
        `${scenario.name}: unexpected km-cap warning in ` +
          JSON.stringify(result.draft.warnings),
      );
    }
  });
}
