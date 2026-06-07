import Image from "next/image";

export function InviteUnavailable() {
  return (
    <main className="share-preview share-preview-unavailable">
      <Image
        src="/brand/mark_white.png"
        alt="Vamo"
        width={72}
        height={72}
        priority
      />
      <h1>Invite not available</h1>
      <p>
        This invite link may be invalid, expired, or already used. Ask your
        trip organizer for a fresh link.
      </p>
      <span className="store-badge">Google Play — coming soon</span>
    </main>
  );
}
