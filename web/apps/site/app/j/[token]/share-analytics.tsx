"use client";

import { useEffect } from "react";
import {
  analyticsChannel,
  captureWebEvent,
} from "../../../lib/analytics";

type Props = {
  channel?: string | null;
  status: "available" | "unavailable";
};

export function SharePageAnalytics({ channel, status }: Props) {
  useEffect(() => {
    captureWebEvent("share_page_viewed", {
      channel: analyticsChannel(channel),
      status,
    });
  }, [channel, status]);

  return null;
}
