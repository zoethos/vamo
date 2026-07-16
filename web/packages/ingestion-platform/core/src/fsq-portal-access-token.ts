/**
 * Pure validation for optional FSQ Places Portal access-token expiry metadata.
 *
 * The token itself remains a server/job secret. This module only evaluates the
 * separately configured expiry timestamp so trusted workers can fail before
 * they claim a commissioning request with a known-expired credential.
 */

export function validateFsqPortalAccessTokenExpiry(input: {
  expiresAt?: string;
  now?: string;
}): { ok: true } | { ok: false; block: "portal_access_token_expiry_invalid" | "portal_access_token_expired" } {
  const expiresAt = input.expiresAt?.trim();
  if (!expiresAt) {
    return { ok: true };
  }

  const expiresAtMs = Date.parse(expiresAt);
  const nowMs = Date.parse(input.now ?? new Date().toISOString());
  if (!Number.isFinite(expiresAtMs) || !Number.isFinite(nowMs)) {
    return { ok: false, block: "portal_access_token_expiry_invalid" };
  }
  if (expiresAtMs <= nowMs) {
    return { ok: false, block: "portal_access_token_expired" };
  }
  return { ok: true };
}
