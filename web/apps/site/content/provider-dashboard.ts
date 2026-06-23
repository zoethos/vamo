export type ProviderDashboardService = {
  service: string;
  purpose: string;
  status: "live" | "planned" | "watch";
  providers: string[];
  freeCapLabel: string;
  cachePolicy: string;
  nextStep: string;
};

export type ProviderDashboardSignal = {
  label: string;
  value: string;
  tone: "good" | "watch" | "neutral";
};

export const providerDashboardServices: ProviderDashboardService[] = [
  {
    service: "POI discovery",
    purpose: "Visit search, place cards, trip map pins",
    status: "live",
    providers: ["Foursquare", "future Google live resolver"],
    freeCapLabel: "500 fresh calls/month safety cap",
    cachePolicy: "Cache-friendly provider content, 7-day POI cache",
    nextStep: "Live usage from service_usage_global",
  },
  {
    service: "FX rates",
    purpose: "Foreign-currency expense conversion",
    status: "watch",
    providers: ["exchangerate.host"],
    freeCapLabel: "Low-volume, rate-limit sensitive",
    cachePolicy: "Trip rates are forward-only snapshots",
    nextStep: "Move fetch path to fx-rates Edge Function",
  },
  {
    service: "Weather",
    purpose: "Trip preview weather badges",
    status: "planned",
    providers: ["Open-Meteo first"],
    freeCapLabel: "Free provider, no key",
    cachePolicy: "Forecast bucket only; silent fallback",
    nextStep: "Adopt premium-service metering shape",
  },
  {
    service: "Theme AI",
    purpose: "Destination theme cache misses",
    status: "planned",
    providers: ["OpenAI-compatible", "future Azure OpenAI"],
    freeCapLabel: "Usage-based; cache misses only",
    cachePolicy: "Global theme cache, validated locally",
    nextStep: "Surface provider_usage_events",
  },
  {
    service: "Transactional email",
    purpose: "OTP and future notification email",
    status: "live",
    providers: ["Brevo", "Resend fallback"],
    freeCapLabel: "Brevo daily free cap",
    cachePolicy: "No content cache; provider fallback only",
    nextStep: "Show fallback usage and send failures",
  },
];

export const providerDashboardSignals: ProviderDashboardSignal[] = [
  {
    label: "Dashboard mode",
    value: "Static read-only shell",
    tone: "neutral",
  },
  {
    label: "Secrets posture",
    value: "No secrets exposed",
    tone: "good",
  },
  {
    label: "Mutation controls",
    value: "Deferred",
    tone: "good",
  },
  {
    label: "Live usage data",
    value: "P1 after admin auth",
    tone: "watch",
  },
];

export const providerDashboardGuardrails = [
  "Never show secret values; only show whether a secret is configured.",
  "Never use service-role data from a public route.",
  "Provider switching requires test call, validation, audit log, and rollback.",
  "Dashboards observe product contracts; they do not redefine them.",
  "Quota gates must fail loud and safe, never silently spend through caps.",
];
