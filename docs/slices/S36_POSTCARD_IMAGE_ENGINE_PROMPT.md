# S36 — WITHDRAWN (rolled back)

This draft incorrectly conflated **Postcard** with AI-generated trip pictures and
proposed "correcting" `POSTCARD_SPEC.md`. That was wrong.

**Postcard stands as originally specced** (`docs/POSTCARD_SPEC.md`): place → visual
backdrop via **real venue photo → static map → fallback**, for **capture/receipt**
backdrops. No change.

AI-generated **trip badge/hero pictures** (+ user upload/replace) are a **separate**
feature, not Postcard — to be specced on its own if/when the founder wants it.

Safe to delete this file (`git clean -f` / rm).
