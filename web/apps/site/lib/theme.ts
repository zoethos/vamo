export type SnapshotThemePack = {
  id: string;
  label: string;
  gradient: string[];
  statBackground: string;
  statPrimary: string;
  statMuted: string;
  accent: string;
  memberBubble: string;
  memberInitial: string;
  tagline?: string;
};

export const defaultThemePack: SnapshotThemePack = {
  id: "default",
  label: "Vamo",
  gradient: ["#FF5B4D", "#6A2D6F"],
  statBackground: "#FFE6EC",
  statPrimary: "#0C0E16",
  statMuted: "#2A2E3A",
  accent: "#FF5B4D",
  memberBubble: "#FFE6EC",
  memberInitial: "#0C0E16",
  tagline: "Si va?",
};

export function parseThemePack(raw: unknown): SnapshotThemePack {
  if (!raw || typeof raw !== "object") return defaultThemePack;
  const value = raw as Record<string, unknown>;
  const gradient = Array.isArray(value.gradient)
    ? value.gradient.filter((c): c is string => typeof c === "string")
    : defaultThemePack.gradient;
  return {
    id: typeof value.id === "string" ? value.id : defaultThemePack.id,
    label:
      typeof value.label === "string" ? value.label : defaultThemePack.label,
    gradient: gradient.length >= 2 ? gradient : defaultThemePack.gradient,
    statBackground:
      typeof value.statBackground === "string"
        ? value.statBackground
        : defaultThemePack.statBackground,
    statPrimary:
      typeof value.statPrimary === "string"
        ? value.statPrimary
        : defaultThemePack.statPrimary,
    statMuted:
      typeof value.statMuted === "string"
        ? value.statMuted
        : defaultThemePack.statMuted,
    accent:
      typeof value.accent === "string" ? value.accent : defaultThemePack.accent,
    memberBubble:
      typeof value.memberBubble === "string"
        ? value.memberBubble
        : defaultThemePack.memberBubble,
    memberInitial:
      typeof value.memberInitial === "string"
        ? value.memberInitial
        : defaultThemePack.memberInitial,
    tagline:
      typeof value.tagline === "string" ? value.tagline : defaultThemePack.tagline,
  };
}

export function themeGradientCss(theme: SnapshotThemePack): string {
  return `linear-gradient(135deg, ${theme.gradient.join(", ")})`;
}
