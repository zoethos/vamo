-- 0030 — URL-safe invite tokens (base64url)
-- Standard base64 (migration 0001) emits '+' and '/', which break the
-- /j/<token> web redeem link (e.g. '+' arrives as %2B and the web redeemer
-- mis-decodes it). Switch the default to base64url so new tokens are URL-safe.
-- Existing '+'/'/' tokens are unaffected and must be reissued (invites are ephemeral).
-- 9 random bytes -> 12 chars, no '=' padding, only '+' and '/' to translate.

alter table invites
  alter column token
  set default replace(replace(encode(extensions.gen_random_bytes(9), 'base64'), '+', '-'), '/', '_');
