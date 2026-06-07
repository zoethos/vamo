"use client";

type AnalyticsProperties = Record<string, string | number | boolean | null>;

const DISTINCT_ID_KEY = "vamo.web.distinct_id";
const DEFAULT_POSTHOG_HOST = "https://eu.i.posthog.com";

function posthogConfig() {
  if (typeof window === "undefined") return null;
  const apiKey = process.env.NEXT_PUBLIC_POSTHOG_API_KEY?.trim();
  if (!apiKey) return null;
  const configuredHost = process.env.NEXT_PUBLIC_POSTHOG_HOST?.trim();
  const host = configuredHost && configuredHost.length > 0
    ? configuredHost
    : DEFAULT_POSTHOG_HOST;
  return { apiKey, host };
}

function distinctId() {
  const existing = window.localStorage.getItem(DISTINCT_ID_KEY);
  if (existing) return existing;
  const next =
    window.crypto?.randomUUID?.() ??
    `web-${Date.now()}-${Math.random().toString(36).slice(2)}`;
  window.localStorage.setItem(DISTINCT_ID_KEY, next);
  return next;
}

export function captureWebEvent(
  eventName: string,
  properties: AnalyticsProperties = {},
) {
  const config = posthogConfig();
  if (!config) return;

  let url: string;
  try {
    url = new URL("/i/v0/e/", config.host).toString();
  } catch {
    return;
  }

  const body = JSON.stringify({
    api_key: config.apiKey,
    distinct_id: distinctId(),
    event: eventName,
    properties: {
      ...properties,
      $process_person_profile: false,
    },
    timestamp: new Date().toISOString(),
  });

  if (navigator.sendBeacon) {
    const sent = navigator.sendBeacon(
      url,
      new Blob([body], { type: "application/json" }),
    );
    if (sent) return;
  }

  void fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body,
    keepalive: true,
  }).catch(() => {});
}

export function analyticsChannel(channel?: string | null) {
  if (channel === "qr" || channel === "contact") return channel;
  return "link";
}
