// Destination visual resolver.
//
// Auth: caller JWT required. Provider keys stay server-side.
// Priority: Foursquare place photo -> OpenAI generated image -> unavailable.

import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  addressFromFoursquareLocation,
  photoUrlFromFoursquarePhotos,
  searchFoursquarePlaces,
} from "../_shared/foursquare_places.ts";
import { generateDestinationImage } from "../_shared/openai_images.ts";

interface DestinationVisualInput {
  destination: string;
  lat?: number;
  lng?: number;
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
  if (!supabaseUrl || !anonKey) return json({ error: "misconfigured" }, 503);

  const input = await readInput(req);
  if (!input) return json({ error: "invalid_input" }, 400);

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: authData } = await userClient.auth.getUser();
  if (!authData?.user) return json({ error: "unauthorized" }, 401);

  const foursquare = await resolveFoursquarePhoto(input);
  if (foursquare) {
    return json({ available: true, ...foursquare });
  }

  const ai = await resolveAiImage(input.destination);
  if (ai) {
    return json({ available: true, ...ai });
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
    return { destination, lat, lng };
  } catch {
    return null;
  }
}

async function resolveFoursquarePhoto(
  input: DestinationVisualInput,
): Promise<Record<string, unknown> | null> {
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
      };
    }
  } catch (error) {
    console.error("destination-visual foursquare failure", error);
  }
  return null;
}

async function resolveAiImage(
  destination: string,
): Promise<Record<string, unknown> | null> {
  const apiKey = Deno.env.get("OPENAI_API_KEY")?.trim();
  if (!apiKey) return null;

  try {
    const generated = await generateDestinationImage({ apiKey, destination });
    return generated == null ? null : { ...generated };
  } catch (error) {
    console.error("destination-visual ai failure", error);
    return null;
  }
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

function json(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
    },
  });
}
