# Wave 4 - Trip Document Inflow

_Evaluation + phased plan. Drafted 2026-06-21. Reframed 2026-06-23._

## Vision

Treat trip documentation as a river flowing into Vamo.

Users should be able to send Vamo the messy material that already exists in real travel life - train
tickets, boarding passes, bus confirmations, hotel bookings, restaurant receipts, museum tickets,
PDF invoices, screenshots, forwarded emails - and Vamo turns it into useful trip structure:

- create a trip if none exists yet;
- add plan items for transport, lodging, visits, activities, and bookings;
- add expenses from receipts;
- attach source evidence privately when useful;
- enrich the Plan, Trip Map, balances, and Wrapped without forcing the user to manually type the trip.

The product promise is spontaneous handling: "Send the document to Vamo, review what it found, accept."

This is not a parser farm. The moat is one shared import engine that accepts many inputs, extracts a
normalized draft, and commits only after user review.

## Product principle

Every inflow follows the same safe lifecycle:

```text
document enters Vamo
  -> normalize source
  -> extract structured draft
  -> match or propose trip
  -> user preview + edits
  -> user accepts
  -> commit through existing trip / plan / expense guards
```

No silent trip creation. No silent trip mutation. No raw ticket/email retention by default.

## Inflow channels

| Channel | Priority | Difficulty | Effort | Feasibility | Why / notes |
|---|---:|---:|---:|---|---|
| Android share sheet: PDF, image, text, calendar | P0 | Medium | 5-8 dev days | High | Best first slice. Low provider risk, visible value, and validates the shared parser/preview engine. |
| In-app capture/import: choose file/photo from Vamo | P0.5 | Low-medium | 2-4 dev days | High | Same engine as Android share, but avoids OS share edge cases. Good fallback and test surface. |
| Forward-to-Vamo email | P1 | High | 8-15 dev days | Feasible | High-wow path for airline/hotel confirmations. Needs inbound email provider, sender/auth checks, spam controls, attachment handling, and async notification. |
| iOS share extension | P1 | High | 8-12 dev days | Feasible | Native extension + app group. Reuses the shared engine; difficulty is Apple/native packaging. |
| Auto-watch personal mailbox | P3 | Very high | 20+ dev days | Not now | OAuth, long-lived mailbox permissions, privacy burden, provider review, revocation, support load. Avoid until real demand. |

## Extraction channels

| Source type | Priority | Difficulty | Effort | Approach |
|---|---:|---:|---:|---|
| Images / screenshots | P0 | Medium | 3-5 dev days | Reuse on-device OCR first, then parse OCR text. No network OCR dependency. |
| PDF text | P0 | Medium | 3-5 dev days | Extract text locally/server-side; send text to parser, not raw PDF when possible. |
| Plain text / shared snippets | P0 | Low | 1-2 dev days | Direct parser input. |
| `.ics` calendar files | P0.5 | Medium | 2-4 dev days | Deterministic parser for dates, location, organizer, title; LLM only for classification/enrichment. |
| Email HTML/body + attachments | P1 | High | 5-10 dev days | Parse schema.org JSON-LD first, strip payment data, then LLM fallback. |
| Boarding-pass barcode / wallet pass | P2 | High | 8-12 dev days | Useful but fragmented. Add after PDF/image/email import proves value. |

## Existing Vamo leverage

This is feasible because Vamo already has much of the downstream plumbing:

- `create_trip` RPC creates a trip shell safely.
- Plan items already support transport, lodging, visit/activity, transfer metadata, RSVP, and map surfaces.
- Expenses and receipt OCR exist.
- Drift + sync outbox support offline-first local writes.
- Supabase Edge Functions are already the provider boundary.
- Provider resilience and observability standards already exist.
- Trip Map / Wrapped become natural consumers of imported structured data.

New work is concentrated in:

- intake adapters;
- source normalization;
- extraction engine;
- import draft schema;
- preview/commit UX;
- inbound email auth and anti-spam for P1.

## Shared architecture

```text
[Android share sheet] ------\
[In-app file/photo import] ---\
[iOS share extension] ---------+--> ShareImportController
[Forward-to-Vamo email] -------/        |
                                        v
                             source normalizer
                         text | pdf_text | ocr_text | ics | email
                                        |
                                        v
                        parse-shared-content Edge Function
                   1. deterministic extraction where possible
                   2. payment/secret redaction
                   3. LLM structured extraction fallback
                   4. confidence + warnings
                                        |
                                        v
                              SharedImport draft
                    trip? | planItems[] | expenses[] | warnings[]
                                        |
                                        v
                         Import preview screen
                 edit fields | choose trip | create trip | reject
                                        |
                                        v
                 commit through existing repositories/RPCs
```

Only intake is platform-specific. Extraction, schema, preview, and commit are shared.

## Data contract

The extraction engine returns a draft, never committed data:

```jsonc
{
  "trip": {
    "destination": "Rome",
    "start_date": "2026-07-10",
    "end_date": "2026-07-16",
    "confidence": 0.92
  },
  "planItems": [
    {
      "kind": "transfer",
      "subtype": "flight",
      "title": "LH 232 MUC -> FCO",
      "starts_at": "2026-07-10T08:30:00Z",
      "ends_at": "2026-07-10T10:00:00Z",
      "metadata": {
        "operator": "Lufthansa",
        "reference": "ABC123",
        "origin": "MUC",
        "destination": "FCO"
      },
      "confidence": 0.89
    }
  ],
  "expenses": [
    {
      "description": "Train ticket",
      "amount_cents": 4820,
      "currency": "EUR",
      "spent_at": "2026-07-10T06:30:00Z",
      "confidence": 0.81
    }
  ],
  "warnings": ["Low confidence on passenger name; not stored."]
}
```

Mapping:

- Flights, trains, buses, ferries, taxis, transfers -> `trip_plan_items.kind = transfer` with subtype metadata.
- Lodging -> `lodging` with address, check-in/out, reservation reference.
- Visits, tours, events -> `visit` or `activity`.
- Receipts -> `expenses`.
- Whole-trip confirmations -> draft trip shell plus plan items.

## Trip matching and creation

Trip matching must be conservative:

1. Match an existing trip only when date range and destination strongly overlap.
2. If multiple trips match, show the chooser.
3. If no trip matches and the draft has enough trip data, propose "Create trip".
4. If no trip matches and the draft is only a receipt, ask the user to choose a trip.
5. Never add an item outside the selected trip's date range. Existing server/date guards remain source of truth.

## Email inflow design

Email is a strong P1 because it matches the natural booking-confirmation workflow, but it is not "easy
peasy" operationally. It is feasible if treated as an authenticated async import channel, not as an
open mailbox.

### Recommended authentication model

Use layered acceptance:

1. Give each user a per-user inbound alias, for example `u_<short_token>@in.vamo.world`.
2. Require the visible sender address to match a registered/verified account email, unless the user
   explicitly links another sender address.
3. Require provider-level authentication results where available: SPF/DKIM/DMARC pass or equivalent
   parsed headers.
4. Create a pending import draft, then ask for user confirmation in-app.
5. For first-time email sender/device, require OTP or magic-link confirmation before parsing/committing.

Why not sender match alone: email `From` can be spoofed. Sender match is useful, but not sufficient by
itself. The safer pattern is alias + sender match + mail-auth pass + in-app/OTP confirmation.

### Spam and abuse controls

- Reject unknown aliases before LLM extraction.
- Reject or quarantine oversized messages and dangerous attachments.
- Rate-limit by alias, sender, IP/provider metadata, and user.
- Do not call paid LLM extraction for untrusted or unauthenticated email.
- Store only a small pending-import envelope until accepted; expire automatically.
- Emit provider usage telemetry before paid calls.

### Provider feasibility

Inbound email is best handled by a provider/webhook rather than polling IMAP.

| Provider path | Fit | Notes |
|---|---|---|
| Postmark inbound | Strong P1 candidate | Parses inbound mail into JSON and POSTs to a webhook; good fit for confirmations and attachments. |
| SendGrid Inbound Parse | Feasible | Established inbound parse webhook; heavier account/config surface. |
| Cloudflare Email Routing + Workers | Feasible, lower-cost/control-heavy | Programmatic email handler; may need more parsing work in our code. Attractive if Vamo moves DNS/email deeper into Cloudflare. |
| Mailgun Routes | Feasible | Strong routing model, but plan/cost should be checked before choosing. |

Decision for P1: pick one provider, document limits/pricing in `docs/architecture/DEPENDENCIES.md`, and
put all inbound mail behind `inbound-email-import` so the provider remains swappable.

## LLM extraction decision

The core strategic decision is adopting a server-side LLM extractor. Deterministic parsing handles the
cheap/high-confidence pieces; the LLM handles the long tail.

Requirements:

- server-side only; no client LLM key;
- no-train / low-retention provider setting;
- schema-constrained output;
- confidence scoring and warnings;
- token/cost cap per import;
- per-user daily/monthly quota;
- full provider telemetry;
- graceful degradation when the provider is down or quota is exhausted.

Do not build vendor-specific parser farms unless a deterministic parser is cheap and broadly useful
(`.ics`, JSON-LD, obvious receipt totals).

## Privacy and retention

Tickets and confirmation emails contain high-risk PII: passenger names, PNRs, addresses, emails,
payment fragments, loyalty numbers, seat numbers, and sometimes passport hints.

Rules:

- Explicit user action only.
- Confirm-before-commit always.
- Strip card numbers, CVV-like values, and payment fragments before LLM calls.
- Do not persist raw source by default.
- If evidence retention is later needed, store a redacted artifact with clear user consent.
- Never store passenger names unless needed for group assignment and accepted by the user.
- Log structured errors and provider usage, never raw source content.

## Prioritized roadmap

### W4.0 - Design and safety gate

- Priority: P0
- Difficulty: Low
- Effort: 1-2 days
- Output: final data contract, source-retention policy, LLM provider decision, cost ceilings, inbound email provider shortlist.
- Done when: product and privacy rules are clear enough for implementation.

### W4.1 - Android share + import preview

- Priority: P0
- Difficulty: Medium
- Effort: 8-12 days
- Scope:
  - Android `ACTION_SEND` / `ACTION_SEND_MULTIPLE` for PDF, image, text, calendar.
  - Shared `ShareImportController`.
  - Source normalization for text, image OCR, PDF text.
  - `parse-shared-content` Edge Function with mocked LLM in tests.
  - `SharedImport` Dart model.
  - Import preview screen.
  - Commit to existing trip or create trip.
- Excludes: inbound email, iOS extension, raw source retention.
- Value: proves the engine and the UX with the lowest operational risk.

### W4.1b - In-app import fallback

- Priority: P0.5
- Difficulty: Low-medium
- Effort: 2-4 days
- Scope:
  - "Import document" action inside trip Plan/Expenses.
  - Pick file/photo and reuse the exact W4.1 pipeline.
- Value: makes the feature discoverable and testable even when OS share behavior varies.

### W4.2 - Parser hardening pack

- Priority: P0.5
- Difficulty: Medium
- Effort: 5-8 days
- Scope:
  - Deterministic JSON-LD extraction.
  - `.ics` parser.
  - confidence thresholds.
  - duplicate detection for already-imported tickets/receipts.
  - provider-cost telemetry dashboard fields.
- Value: reduces LLM spend and improves trust before email volume arrives.

### W4.3 - Forward-to-Vamo email

- Priority: P1
- Difficulty: High
- Effort: 10-18 days
- Scope:
  - inbound email provider setup on a subdomain such as `in.vamo.world`;
  - per-user alias generation;
  - sender match + SPF/DKIM/DMARC/auth result checks;
  - pending import table with expiry;
  - OTP/magic-link confirmation for first-time email inflow;
  - attachment normalization;
  - notification "Vamo found a trip document - review it";
  - same preview/commit flow as W4.1.
- Value: highest "wow" moment, especially for airline/hotel confirmations.
- Main risk: spam/cost/PII. Do not call LLM until the email is trusted.

### W4.4 - iOS share extension

- Priority: P1
- Difficulty: High
- Effort: 8-12 days
- Scope:
  - iOS share extension target;
  - app group handoff;
  - pass normalized payload to shared controller;
  - reuse preview/commit.
- Value: platform parity.

### W4.5 - Advanced travel artifacts

- Priority: P2
- Difficulty: High
- Effort: 10-20 days
- Scope:
  - wallet passes;
  - boarding-pass barcode parsing;
  - richer route/seat/gate metadata;
  - post-import change detection.
- Value: polish after the main inflow works.

## Testing and CI guardrails

- Unit tests for `SharedImport` parsing, confidence handling, and unknown-field tolerance.
- Edge tests for JSON-LD, `.ics`, payment redaction, malformed LLM output, and provider timeouts.
- Widget tests for preview/edit/commit.
- RLS smoke for commit paths, not hundreds of paid provider calls.
- Provider tests must mock LLM and inbound email by default.
- Any live provider smoke requires explicit human approval and must use one bounded fixture.
- CI guard: no test may call the paid LLM or inbound provider unless an explicit live-smoke flag is set.

## Difficulty summary

| Area | Difficulty | Why |
|---|---|---|
| Android intake | Medium | Native manifest and app lifecycle edge cases, but known pattern. |
| Extraction engine | High | PII, schema quality, hallucination control, cost caps. |
| Preview UX | Medium | Many object types but uses existing Plan/Expense models. |
| Commit path | Medium | Must preserve existing RLS/RPC/outbox rules. |
| Email inflow | High | Spam, sender spoofing, attachments, async UX, provider config. |
| iOS extension | High | Native packaging and app group handoff. |

## Recommended next move

Do W4.0 and W4.1 first. Add W4.1b if share-sheet testing feels brittle. Pull email into the architecture
now, but keep it as W4.3 so the engine is already real before exposing an inbound address to the world.

The refined product line:

> Vamo is the inbox for your trip documents. Share or forward the ticket, receipt, or booking; Vamo
> turns it into a trip draft you can trust, edit, and accept.
