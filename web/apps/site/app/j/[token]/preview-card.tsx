import Image from "next/image";
import type { TripPreview } from "../../../lib/trip-preview";
import {
  formatTripDates,
  memberCountLabel,
} from "../../../lib/trip-preview";
import { themeGradientCss } from "../../../lib/theme";
import { InviteCtas } from "./invite-ctas";

type Props = {
  token: string;
  channel?: string | null;
  preview: TripPreview;
};

export function TripPreviewCard({ token, channel, preview }: Props) {
  const dates = formatTripDates(preview.startDate, preview.endDate);
  const heroStyle = { background: themeGradientCss(preview.theme) };

  return (
    <main className="share-preview">
      <article
        className="share-preview-card"
        style={{
          ["--preview-stat-bg" as string]: preview.theme.statBackground,
          ["--preview-stat-primary" as string]: preview.theme.statPrimary,
          ["--preview-stat-muted" as string]: preview.theme.statMuted,
          ["--preview-accent" as string]: preview.theme.accent,
        }}
      >
        <div className="share-preview-hero" style={heroStyle}>
          <Image
            src="/brand/mark_white.png"
            alt="Vamo"
            width={56}
            height={56}
            priority
            className="share-preview-watermark"
          />
          {preview.theme.tagline ? (
            <p className="share-preview-tagline">{preview.theme.tagline}</p>
          ) : null}
        </div>
        <div className="share-preview-body">
          <h1>{preview.tripName}</h1>
          {preview.destination ? (
            <p className="share-preview-destination">{preview.destination}</p>
          ) : null}
          {dates ? <p className="share-preview-dates">{dates}</p> : null}
          <p className="share-preview-members">
            {memberCountLabel(preview.memberCount)}
          </p>
          <InviteCtas token={token} channel={channel} />
        </div>
      </article>
    </main>
  );
}
