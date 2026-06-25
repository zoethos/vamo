// Destination visual resolver.
//
// Auth: caller JWT required. Provider keys stay server-side.
// Priority: provider-safe place photo -> unavailable.

import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";
import {
  addressFromFoursquareLocation,
  photoUrlFromFoursquarePhotos,
  searchFoursquarePlaces,
} from "../_shared/foursquare_places.ts";
import {
  recordLocationObservation,
  runInBackground,
} from "../_shared/place_intelligence.ts";

interface DestinationVisualInput {
  destination: string;
  lat?: number;
  lng?: number;
  tripId?: string | null;
  observationKind?: "manual_find" | "create_trip_background";
}

interface DestinationVisualResult {
  source: string;
  imageUrl?: string;
  title?: string;
  subtitle?: string;
  providerPlaceId?: string;
  attribution?: string;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "authorization, content-type",
      },
    });
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "unauthorized" }, 401);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey) return json({ error: "misconfigured" }, 503);

  const input = await readInput(req);
  if (!input) return json({ error: "invalid_input" }, 400);

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: authData } = await userClient.auth.getUser();
  const user = authData?.user;
  if (!user) return json({ error: "unauthorized" }, 401);

  if (input.tripId) {
    const { data: trip, error: tripError } = await userClient
      .from("trips")
      .select("id")
      .eq("id", input.tripId)
      .maybeSingle();
    if (tripError || !trip) return json({ error: "trip_not_found" }, 404);
  }

  const serviceClient = serviceKey
    ? createClient(supabaseUrl, serviceKey)
    : null;

  const foursquare = await resolveFoursquarePhoto(input);
  if (foursquare) {
    if (serviceClient) {
      scheduleObservation(serviceClient, {
        input,
        userId: user.id,
        result: foursquare,
        selected: true,
      });
    }
    return json({ available: true, ...foursquare });
  }

  if (serviceClient) {
    scheduleObservation(serviceClient, {
      input,
      userId: user.id,
      selected: false,
    });
  }
  return json({ available: false, reason: "no_visual_available" });
});

async function readInput(req: Request): Promise<DestinationVisualInput | null> {
  try {
    const body = await req.json();
    if (body == null || typeof body !== "object") return null;
    const row = body as Record<string, unknown>;
    const destination = stringValue(row.destination);
    if (!destination || destination.length < 2 || destination.length > 80) {
      return null;
    }
    const lat = numberValue(row.lat);
    const lng = numberValue(row.lng);
    return {
      destination,
      lat,
      lng,
      tripId: stringValue(row.trip_id) ?? stringValue(row.tripId) ?? null,
      observationKind: observationKindValue(row.observation_kind) ??
        observationKindValue(row.observationKind) ?? "manual_find",
    };
  } catch {
    return null;
  }
}

async function resolveFoursquarePhoto(
  input: DestinationVisualInput,
): Promise<DestinationVisualResult | null> {
  const apiKey = Deno.env.get("FOURSQUARE_API_KEY")?.trim();
  if (!apiKey) return null;

  try {
    const raw = await searchFoursquarePlaces({
      apiKey,
      near: input.lat == null || input.lng == null ? input.destination : null,
      lat: input.lat,
      lng: input.lng,
      radius: 25000,
      query: input.destination,
      limit: 8,
      fields: ["fsq_place_id", "name", "location", "photos"],
    });
    const rows = Array.isArray((raw as { results?: unknown[] })?.results)
      ? (raw as { results: unknown[] }).results
      : [];
    for (const row of rows) {
      if (row == null || typeof row !== "object") continue;
      const place = row as Record<string, unknown>;
      const imageUrl = photoUrlFromFoursquarePhotos(place.photos, "original");
      if (!imageUrl) continue;
      return {
        source: "foursquare",
        imageUrl,
        title: stringValue(place.name) ?? input.destination,
        subtitle: addressFromFoursquareLocation(place.location),
        providerPlaceId: stringValue(place.fsq_place_id),
        attribution: "Foursquare Places API live response",
      };
    }
  } catch (error) {
    console.error("destination-visual foursquare failure", error);
  }
  return null;
}

function scheduleObservation(
  supabase: SupabaseClient,
  args: {
    input: DestinationVisualInput;
    userId: string;
    result?: DestinationVisualResult;
    selected: boolean;
  },
): void {
  runInBackground(
    recordLocationObservation(supabase, {
      userId: args.userId,
      tripId: args.input.tripId,
      query: args.input.destination,
      resolvedDisplayName: args.result?.title ?? null,
      resolvedFeatureType: "poi",
      resolvedLat: args.input.lat ?? null,
      resolvedLng: args.input.lng ?? null,
      provider: args.result?.providerPlaceId ? "foursquare_places_api" : null,
      providerPlaceId: args.result?.providerPlaceId ?? null,
      sourceAttribution: args.result?.attribution ?? null,
      trustedSourceMatch: false,
      observationKind: args.input.observationKind ?? "manual_find",
      selected: args.selected,
      metadata: {
        resolver: "destination-visual",
        visual_source: args.result?.source ?? null,
        has_image: args.result?.imageUrl != null,
      },
    }),
    "destination-visual observation",
  );
}

function stringValue(raw: unknown): string | undefined {
  if (typeof raw !== "string") return undefined;
  const trimmed = raw.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

function numberValue(raw: unknown): number | undefined {
  if (typeof raw === "number" && Number.isFinite(raw)) return raw;
  if (typeof raw !== "string") return undefined;
  const parsed = Number(raw);
  return Number.isFinite(parsed) ? parsed : undefined;
}

function observationKindValue(
  raw: unknown,
): DestinationVisualInput["observationKind"] | undefined {
  switch (stringValue(raw)) {
    case "manual_find":
    case "create_trip_background":
      return stringValue(raw) as DestinationVisualInput["observationKind"];
    default:
      return undefined;
  }
}

function json(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
    },
  });
}
