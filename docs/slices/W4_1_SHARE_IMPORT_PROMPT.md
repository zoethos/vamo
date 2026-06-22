# W4.1 - Trip document inflow: Android share + smart import (P0)

**Why.** First build slice of Wave 4 (`docs/specs/wave4-share-to-vamo.md`). Wave 4 is the **trip
document inflow** system: tickets, receipts, bookings, screenshots, calendar files, and later
forwarded emails become structured trip drafts. This slice lets a user share a ticket / receipt /
booking PDF / image / text into Vamo from the Android share sheet; Vamo extracts structured data and
lets them **add it to a trip or create a trip from scratch**. Builds the **shared extraction engine +
import-preview flow** that in-app import (W4.1b), email (W4.3), and iOS (W4.4) reuse unchanged.

**Scope = P0.** Android intake (files/images/text) -> `parse-shared-content` edge function -> import
preview -> commit. **No email, no iOS** here. **Confirm-before-commit always** - never silently create
or modify a trip. Email is designed now as W4.3, but no inbound address is exposed in this slice.

**Cross-platform seam (mandatory).** Only **A** below is Android-specific. **B/C/D (engine, schema,
preview, commit) are platform-agnostic Dart/backend** so W4.2 iOS only adds a share extension. Keep
the intake handler thin: it normalizes the share payload to `(text?, files[])` and hands off to the
shared `ShareImportController` — no parsing logic in the platform layer.

## A. Android intake (platform-specific)
- `AndroidManifest.xml`: add `ACTION_SEND` + `ACTION_SEND_MULTIPLE` intent-filters for
  `application/pdf`, `image/*`, `text/plain`, `text/calendar`. Keep existing `VIEW` (App Links) filters.
- Use **`receive_sharing_intent`** for cold-start + warm-stream shares. On receipt, route to a new
  `ShareImportController.ingest(text?, files[])` and navigate to the import-preview route.
- Reuse the existing on-device OCR (`receipt_ocr_*`) to turn shared **images** into text before
  extraction; extract text from **PDFs**; pass **text/.ics** through as-is.

## B. `parse-shared-content` edge function (Deno, shared)
- Input: `{ kind: 'text'|'pdf_text'|'ocr_text'|'ics', content: string, hint?: string }` (auth required —
  user JWT). Mirror the `fx-rates`/`weather-forecast` conventions (CORS, `json()` helper).
- Pipeline: **(1)** parse **schema.org JSON-LD** (`FlightReservation`/`LodgingReservation`/`EventReservation`)
  if present — deterministic. **(2)** strip obvious **payment PII** (card numbers/CVV) before any LLM
  call. **(3)** call **Claude with structured output** (the schema in C) for anything JSON-LD didn't
  cover. **(4)** return the normalized payload. **Do not persist** the raw input.
- Secrets: `ANTHROPIC_API_KEY` (function secret; **no client key**). Use a **no-train** endpoint; cap
  tokens; add a per-user rate limit.

## C. Structured output schema (the contract — keep stable across platforms)
```jsonc
{
  "trip": {                      // present only when the content implies a whole trip
    "destination": "Rome",
    "start_date": "2026-07-10",
    "end_date": "2026-07-16",
    "confidence": 0.0-1.0
  },
  "planItems": [
    { "kind": "transfer", "subtype": "flight",          // maps to S53 transfer taxonomy
      "title": "LH 232 MUC→FCO",
      "starts_at": "...", "ends_at": "...",
      "metadata": { "operator": "Lufthansa", "reference": "ABC123",
                    "origin": "MUC", "destination": "FCO" },
      "confidence": 0.0-1.0 },
    { "kind": "lodging", "title": "Hotel Artemide",
      "starts_at": "...", "ends_at": "...",
      "metadata": { "address": "..." }, "confidence": 0.0-1.0 }
  ],
  "expenses": [
    { "description": "Dinner", "amount_cents": 4820, "currency": "EUR",
      "spent_at": "...", "confidence": 0.0-1.0 }
  ],
  "warnings": ["low confidence on hotel dates"]
}
```
Mirror this as a Dart model (`SharedImport`); unknown fields ignored; `confidence` drives the preview.

## D. Import-preview screen (shared Dart — platform-agnostic)
- Route `share-import`. Shows the parsed result grouped (trip / plan items / expenses); each field
  **editable**; low-`confidence` fields visibly flagged.
- Destination chooser: **"Add to <existing trip>"** (trip picker) **or "Create new trip"** (uses the
  `trip.*` block + lets the user adjust). Nothing commits until the user taps **Import**.
- On Import: commit via existing repos — `create_trip` RPC (if new) → `plan_repository` for plan items
  (transfer/lodging/etc., S53 metadata) → `expenses_repository` for receipts. Reuse the propose/insert
  paths; don't bypass their RPC/guards.
- Trip matching is conservative: suggest a trip only when date/destination overlap is strong; otherwise
  make the user choose. Never import an item outside the selected trip date range.

## E. Tests
- **Dart:** `SharedImport` parse (incl. `trip:null`, empty arrays, unknown fields); the intake handler
  normalizes text vs files correctly; preview renders + flags low-confidence; commit calls the right
  repos for new-trip vs add-to-trip.
- **Edge:** JSON-LD extraction for a `FlightReservation` sample (deterministic path, no LLM); payment-PII
  stripping; schema-validation of the LLM output (reject malformed). Mock the LLM in unit tests.
- **rls_smoke:** a member can call `parse-shared-content`; committing creates plan items/expenses on a
  trip they own/co-admin (existing guards apply); an outsider can't commit to a foreign trip.

## F. Guardrails / done =
- **Confirm-before-commit** — no silent trip create/modify. PII stripped; raw input not persisted; LLM
  is no-train + token/rate-capped.
- Intake is the only Android-specific code; engine + schema + preview + commit are shared so **W4.2 iOS
  is just a share extension** against the same `ShareImportController`.
- Maps to the real model: flights/trains→`transfer`(+subtype), hotels→`lodging`/`stay`, receipts→
  `expenses`, trip shell→`create_trip`. No new plan kinds needed.
- New edge fn deployed to **staging** (`sfwziwcuyctxvidivnsh`, **not** prod — CLI links to prod) +
  `rls_smoke` green; `melos run ci` green; goldens on **Linux** if the preview adds a golden surface;
  watch the `AppColors` ratchet.
- Greenlight required before building: the **LLM backend** (`ANTHROPIC_API_KEY`, cost/PII policy).

## Notes
- **Branch base:** off `main`; own worktree.
- W4.1b (in-app import), W4.3 (forward-to-Vamo email), and W4.4 (iOS share extension) are separate
  slices that reuse B/C/D.
- Don't pull email forward into P0. Email is high-value but needs alias/sender auth, OTP/magic-link
  confirmation for first-time senders, spam controls, and paid-provider guardrails (see the spec).
