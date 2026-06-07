import type { Metadata } from "next";
import { canonicalJoinLanding } from "../../../lib/invite-urls";
import { fetchTripPreview } from "../../../lib/trip-preview";
import { InviteUnavailable } from "./unavailable";
import { TripPreviewCard } from "./preview-card";

export const dynamic = "force-dynamic";
export const revalidate = 0;

type Props = {
  params: Promise<{ token: string }>;
  searchParams: Promise<{ ch?: string }>;
};

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { token } = await params;
  const preview = await fetchTripPreview(token);
  if (!preview) {
    return {
      title: "Invite not available · Vamo",
      description: "This invite link is no longer available.",
      robots: { index: false, follow: false },
      alternates: { canonical: canonicalJoinLanding() },
    };
  }
  const descriptionParts = [
    preview.destination,
    preview.memberCount === 1
      ? "1 Vamigo going"
      : `${preview.memberCount} Vamigos going`,
  ].filter(Boolean);
  return {
    title: `${preview.tripName} · Vamo`,
    description:
      descriptionParts.length > 0
        ? descriptionParts.join(" · ")
        : "You're invited to join a trip on Vamo.",
    robots: { index: false, follow: false },
    alternates: { canonical: canonicalJoinLanding() },
    openGraph: {
      title: preview.tripName,
      description:
        descriptionParts.length > 0
          ? descriptionParts.join(" · ")
          : "Join this trip on Vamo.",
      siteName: "Vamo",
      type: "website",
    },
    twitter: {
      card: "summary_large_image",
      title: preview.tripName,
      description:
        descriptionParts.length > 0
          ? descriptionParts.join(" · ")
          : "Join this trip on Vamo.",
    },
  };
}

export default async function JoinPage({ params, searchParams }: Props) {
  const { token } = await params;
  const { ch } = await searchParams;
  const preview = await fetchTripPreview(token);

  if (!preview) {
    return <InviteUnavailable />;
  }

  return <TripPreviewCard token={token} channel={ch ?? null} preview={preview} />;
}
