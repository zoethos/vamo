import { assert, assertEquals } from "jsr:@std/assert@1.0.19";

// PDA-0 guard.
//
// `location_provider_policies` seeds `foursquare_places_api` with
// `can_store_content = false`, so the provider's place title must never reach
// `location_observations.resolved_display_name`. It may still be returned live
// in the response — this guards persistence only.
//
// The check is deliberately a source assertion rather than a unit test:
// `index.ts` calls `Deno.serve` at module scope, so importing it would start a
// server, and `scheduleObservation` is not exported. PDA-2 replaces this with
// write-time policy enforcement in the shared writer plus a database trigger,
// at which point this guard can go.

const source = Deno.readTextFileSync(new URL("./index.ts", import.meta.url));

function observationPayload(): string {
  const start = source.indexOf("recordLocationObservation(supabase, {");
  assert(start >= 0, "recordLocationObservation call not found in index.ts");
  const end = source.indexOf("\n    }),", start);
  assert(
    end > start,
    "could not delimit the recordLocationObservation payload",
  );
  return source.slice(start, end);
}

Deno.test("destination-visual does not persist the Foursquare place title", () => {
  const payload = observationPayload();

  assert(
    !/resolvedDisplayName:\s*args\.result\?\.title/.test(payload),
    "provider title must not be written to resolved_display_name",
  );
  assert(
    !/\.title/.test(payload),
    "no provider title field may be passed into the observation payload",
  );
});

Deno.test("destination-visual passes an explicit null display name", () => {
  assert(
    /resolvedDisplayName:\s*null/.test(observationPayload()),
    "resolvedDisplayName should be explicitly null to document the policy intent",
  );
});

Deno.test("destination-visual still records the permitted provider fields", () => {
  const payload = observationPayload();

  // `can_store_place_id = true` and `requires_attribution = true`, so both stay.
  assert(
    /providerPlaceId:\s*args\.result\?\.providerPlaceId/.test(payload),
    "provider place id is permitted and must still be recorded",
  );
  assert(
    /sourceAttribution:\s*args\.result\?\.attribution/.test(payload),
    "attribution is required by policy and must still be recorded",
  );

  // Coordinates come from request input, not the provider response, so they are
  // Vamo-owned and must survive the redaction.
  assertEquals(/resolvedLat:\s*args\.input\.lat/.test(payload), true);
  assertEquals(/resolvedLng:\s*args\.input\.lng/.test(payload), true);
});
