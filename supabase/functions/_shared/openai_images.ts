const OPENAI_IMAGE_URL = "https://api.openai.com/v1/images/generations";

export interface DestinationImageRequest {
  apiKey: string;
  destination: string;
  model?: string;
  size?: string;
  fetcher?: typeof fetch;
}

export interface GeneratedImage {
  source: "ai";
  imageBase64?: string;
  imageUrl?: string;
  mimeType?: string;
  title: string;
}

export async function generateDestinationImage(
  request: DestinationImageRequest,
): Promise<GeneratedImage | null> {
  const destination = request.destination.trim();
  if (destination.length < 2) return null;
  const fetcher = request.fetcher ?? fetch;
  const response = await fetcher(OPENAI_IMAGE_URL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${request.apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: request.model ?? "gpt-image-1",
      prompt: destinationImagePrompt(destination),
      size: request.size ?? "1024x1024",
      n: 1,
    }),
  });
  if (!response.ok) return null;

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
  return null;
}

export function destinationImagePrompt(destination: string): string {
  return `Create a realistic scenic travel photograph for ${destination}. ` +
    "No people, no text, no logos. Make it suitable as a mobile trip card background.";
}

function stringValue(raw: unknown): string | undefined {
  if (typeof raw !== "string") return undefined;
  const trimmed = raw.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}
