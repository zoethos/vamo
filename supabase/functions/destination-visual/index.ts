// Destination visual resolver.
//
// Auth: caller JWT required. Provider keys stay server-side.
// Priority: Foursquare place photo -> OpenAI generated image -> unavailable.

import { createClient } from "jsr:@supabase/supabase-js@2";

const FOURSQUARE_SEARCH = "https://places-api.foursquare.com/places/search";
const FOURSQUARE_API_VERSION = "2025-06-17";
const OPENAI_IMAGE_URL = "https://api.openai.com/v1/images/generations";

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

  const url = new URL(FOURSQUARE_SEARCH);
  if (input.lat != null && input.lng != null) {
    url.searchParams.set("ll", `${input.lat},${input.lng}`);
    url.searchParams.set("radius", "25000");
  } else {
    url.searchParams.set("near", input.destination);
  }
  url.searchParams.set("query", input.destination);
  url.searchParams.set("limit", "8");
  url.searchParams.set(
    "fields",
    ["fsq_place_id", "name", "location", "photos"].join(","),
  );

  try {
    const response = await fetch(url, {
      headers: {
        Authorization: `Bearer ${apiKey}`,
        Accept: "application/json",
        "X-Places-Api-Version": FOURSQUARE_API_VERSION,
      },
    });
    if (!response.ok) return null;
    const body = await response.json();
    const rows = Array.isArray(body?.results) ? body.results : [];
    for (const row of rows) {
      if (row == null || typeof row !== "object") continue;
      const place = row as Record<string, unknown>;
      const imageUrl = photoUrlFromPhotos(place.photos);
      if (!imageUrl) continue;
      return {
        source: "foursquare",
        imageUrl,
        title: stringValue(place.name) ?? input.destination,
        subtitle: addressFromLocation(place.location),
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
    const response = await fetch(OPENAI_IMAGE_URL, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "gpt-image-1",
        prompt:
          `Create a realistic scenic travel photograph for ${destination}. ` +
          "No people, no text, no logos. Make it suitable as a mobile trip card background.",
        size: "1024x1024",
        n: 1,
      }),
    });
    if (!response.ok) {
      console.error("destination-visual ai status", response.status);
      return null;
    }
    const body = await response.json();
    const first = Array.isArray(body?.data) ? body.data[0] : null;
    if (first == null || typeof first !== "object") return null;
    const row = first as Record<string, unknown>;
    const imageBase64 = stringValue(row.b64_json);
    if (imageBase64) {
      return {
        source: "ai",
        imageBase64,
        mimeType: "image/png",
        title: destination,
      };
    }
    const imageUrl = stringValue(row.url);
    if (imageUrl) {
      return {
        source: "ai",
        imageUrl,
        title: destination,
      };
    }
  } catch (error) {
    console.error("destination-visual ai failure", error);
  }
  return null;
}

function photoUrlFromPhotos(raw: unknown): string | undefined {
  if (!Array.isArray(raw) || raw.length === 0) return undefined;
  for (const entry of raw) {
    if (entry == null || typeof entry !== "object") continue;
    const photo = entry as Record<string, unknown>;
    const directUrl = stringValue(photo.url);
    if (directUrl) return directUrl;
    const prefix = stringValue(photo.prefix);
    const suffix = stringValue(photo.suffix);
    if (prefix && suffix) return `${prefix}original${suffix}`;
  }
  return undefined;
}

function addressFromLocation(raw: unknown): string | undefined {
  if (raw == null || typeof raw !== "object") return undefined;
  const location = raw as Record<string, unknown>;
  const joined = [location.locality, location.region, location.country]
    .map(stringValue)
    .filter((value): value is string => value != null)
    .join(", ");
  return stringValue(location.formatted_address) ??
    (joined.length > 0 ? joined : undefined);
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
