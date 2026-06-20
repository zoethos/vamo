"use client";

import { appInviteUrl } from "../../../lib/invite-urls";
import {
  analyticsChannel,
  captureWebEvent,
} from "../../../lib/analytics";

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
          captureWebEvent("share_open_app_tapped", {
            channel: analyticsChannel(channel),
          });
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
