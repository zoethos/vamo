import Image from "next/image";
import type { Metadata } from "next";
import { JoinRedirect } from "./join-redirect";

type Props = {
  params: Promise<{ token: string }>;
};

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { token } = await params;
  const appUrl = `app.vamo://join?token=${encodeURIComponent(token)}`;
  return {
    title: "Join trip · Vamo",
    description: "Open this invite in the Vamo app.",
    other: {
      refresh: `0;url=${appUrl}`,
    },
  };
}

export default async function JoinPage({ params }: Props) {
  const { token } = await params;
  const appUrl = `app.vamo://join?token=${encodeURIComponent(token)}`;

  return (
    <main className="join-card">
      <Image
        src="/brand/mark_white.png"
        alt="Vamo"
        width={72}
        height={72}
        priority
      />
      <h1>Vamo opens this invite — get the app</h1>
      <p>
        If Vamo is installed, your device should open the trip automatically.
        Otherwise install the app and try again.
      </p>
      <span className="store-badge">Google Play — coming soon</span>
      <JoinRedirect appUrl={appUrl} />
    </main>
  );
}
