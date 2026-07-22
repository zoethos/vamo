# OSV Exceptions

## GHSA-f88m-g3jw-g9cj: Sharp below 0.35.0

**Status:** temporary, narrowly scoped exception in [`web/osv-scanner.toml`](../../web/osv-scanner.toml).

**Review deadline:** 2026-08-21. The exception must be removed as soon as a stable
Next.js release resolves `sharp >= 0.35.0`; do not extend it without repeating this
reachability review.

### Current reachability assessment

- `sharp@0.34.5` is transitive through Next.js and is not a declared dependency of
  any Vamo or Confluendo workspace.
- The Confluendo console does not import `next/image`.
- The public Vamo site uses `next/image` only for fixed, repository-owned local
  assets under `/brand/`.
- No Next.js application configures `images.remotePatterns` or `images.domains`.

As a result, no untrusted or remote image bytes currently reach Sharp. The
`web/scripts/osv-sharp-reachability-guard.mjs` CI guard turns those conditions into
an executable contract.

### Immediate removal triggers

Remove this exception before merging any change that does one of the following:

- configures `remotePatterns` or `domains` for a Next.js image optimizer;
- adds a dynamic or non-`/brand/` `next/image` source;
- imports `next/image` in Confluendo or another non-public-site surface; or
- adds `sharp` as a direct dependency.

Those changes make the advisory potentially reachable and require a supported
patched Sharp/Next.js resolution first.
