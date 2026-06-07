const WEB_HOST = "vamo.world";

export function appInviteUrl(token: string, channel?: string | null): string {
  const params = new URLSearchParams({ token });
  if (channel && channel !== "link") {
    params.set("ch", channel);
  }
  return `app.vamo://join?${params.toString()}`;
}

export function webInvitePath(token: string, channel?: string | null): string {
  const base = `/j/${encodeURIComponent(token)}`;
  if (!channel || channel === "link") return base;
  return `${base}?ch=${encodeURIComponent(channel)}`;
}

export function canonicalJoinLanding(): string {
  return `https://${WEB_HOST}/`;
}
