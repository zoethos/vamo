"use client";

import { appInviteUrl } from "../../../lib/invite-urls";

type Props = {
  token: string;
  channel?: string | null;
};

export function InviteCtas({ token, channel }: Props) {
  const appUrl = appInviteUrl(token, channel);

  return (
    <div className="invite-ctas">
      <button
        type="button"
        className="invite-cta invite-cta-primary"
        onClick={() => {
          window.location.href = appUrl;
        }}
      >
        Open in app
      </button>
      <button type="button" className="invite-cta invite-cta-secondary" disabled>
        Get the app — Google Play coming soon
      </button>
    </div>
  );
}
