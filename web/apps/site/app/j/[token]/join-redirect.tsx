"use client";

import { useEffect } from "react";

export function JoinRedirect({ appUrl }: { appUrl: string }) {
  useEffect(() => {
    window.location.replace(appUrl);
  }, [appUrl]);

  return null;
}
