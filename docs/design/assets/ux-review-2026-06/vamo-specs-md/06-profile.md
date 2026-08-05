# Implementation Prompt — Profile & settings · screen 06

**For:** Codex / Claude Code · **Stack:** Flutter + M3 · **Source:** `Vamo UX Improvements.dc.html` §06 (Proposed frame). Tokens & rules: `_DESIGN-TOKENS.md`. The "Current" flat-header-list frame is the rejected build.

**The fix (review M4):** today Profile is one long scroll of section headers with no identity and a Save that scrolls away. Give it a header and a rhythm.

---

## Layout

**1 · Profile header** (no app-bar title — the header is the identity). A brand-gradient band `linear-gradient(135deg,#6A2D6F,#FF5B4D)`, padding 18px:
- A 58px circle avatar (orange bg, 2.5px white border, initial "Y") + a text block: "You · Yara M." 18px/700 white, "yara@email.com" 12px white/.9, and a warm pill "Si va? · 6 trips together" (11px/600 white, bg `rgba(255,255,255,.2)`, radius 999px).

**2 · M3 list sections** (padding 14px 16px). Each group: a small uppercase section label in **plum** 11px/700 (.06em), then list rows. Each row: leading 20px `slate` MSO icon + label 14px (flex) + trailing current-value 13px `mute2` (or a `chevron_right` for drill-ins). Rows divided by 1px `#F0F1F4`; last row in a group has no divider.
- **ACCOUNT:** Display name (`badge` → "Yara M."), Default currency (`payments` → "EUR"), Theme (`dark_mode` → "Plum").
- **PRIVACY:** Location precision (`location_on` → "Approx"), Export my data (`download` → chevron).

**3 · Pinned save.** Bottom, on a 1px `#E9ECF2` top border: a full-width **"Save changes"** button — **`ink` fill + white text, NOT lime.** (Or autosave + snackbar.) Settings save is not the app's signature action.

## Why (carry verbatim)
- **Profile header** — avatar, name, warm "Si va? · 6 trips together" line on the brand gradient. Identity instead of a cold settings list.
- **M3 list sections** with leading icons, current-value trailing text, dividers — scannable rhythm in place of a flat run of headers.
- **Pinned save** (or autosave + snackbar) so it never scrolls away — and it's **ink, not lime**: lime stays reserved for the core loop (FAB, Settle, Share).
