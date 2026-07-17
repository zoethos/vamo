/**
 * Server/job-only time budget for a bounded FSQ Places Portal query.
 *
 * Portal/Iceberg reads can legitimately take longer than an interactive request,
 * but the worker must still have a finite, operator-configurable deadline.
 */
export const FSQ_PORTAL_QUERY_TIMEOUT_ENV = "FSQ_OS_PLACES_PORTAL_QUERY_TIMEOUT_MS" as const;
export const FSQ_PORTAL_QUERY_DEFAULT_TIMEOUT_MS = 300_000;
export const FSQ_PORTAL_QUERY_MIN_TIMEOUT_MS = 30_000;
export const FSQ_PORTAL_QUERY_MAX_TIMEOUT_MS = 900_000;

export type ResolveFsqPortalQueryTimeoutResult =
  | { ok: true; timeoutMs: number }
  | { ok: false; block: "portal_query_timeout_invalid" };

export function resolveFsqPortalQueryTimeoutMs(
  raw: string | undefined
): ResolveFsqPortalQueryTimeoutResult {
  if (raw === undefined || raw.trim() === "") {
    return { ok: true, timeoutMs: FSQ_PORTAL_QUERY_DEFAULT_TIMEOUT_MS };
  }

  const timeoutMs = Number(raw.trim());
  if (
    !Number.isSafeInteger(timeoutMs) ||
    timeoutMs < FSQ_PORTAL_QUERY_MIN_TIMEOUT_MS ||
    timeoutMs > FSQ_PORTAL_QUERY_MAX_TIMEOUT_MS
  ) {
    return { ok: false, block: "portal_query_timeout_invalid" };
  }

  return { ok: true, timeoutMs };
}
