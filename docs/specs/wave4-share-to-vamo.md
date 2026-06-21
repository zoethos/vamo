# Wave 4 — Share to Vamo / smart import

_Evaluation + phased plan. Drafted 2026-06-21._

**Vision.** Let users **share a ticket, receipt, or booking-confirmation into Vamo** from any app's
share sheet (and, later, by forwarding a confirmation email), and have Vamo **parse it into structured
trip data** — adding plan items / expenses to an existing trip, or **creating a whole trip from
scratch** (dates, destination, flights, hotel) from a single Lufthansa / Booking.com / Airbnb
confirmation. Frictionless, template-free import is a **moat**: it compounds (more imported bookings →
richer trips → better Trip Map / Wrapped) and competitors with per-vendor parser farms can't match it
cheaply.

## Two problems, very different feasibility
Keep these separate — they have different mechanisms, risks, and platforms.

1. **Ingestion** — getting the raw content into Vamo (OS share sheet / share extension / inbound email).
2. **Extraction** — turning heterogeneous content (PDF, image, email, text) into normalized trip data.

## Feasibility

### Ingestion
| Path | Feasibility | Mechanism |
|---|---|---|
| **Android share sheet** (PDF, image, text, `.ics`) | **High** | `ACTION_SEND` / `ACTION_SEND_MULTIPLE` intent-filters + `receive_sharing_intent`. The app already handles incoming intents (App Links `/j`), so it's incremental. |
| **iOS share extension** | **Feasible, heavier** | A separate **share-extension target** + an **app group** to hand data to the main app. Same `receive_sharing_intent` package supports it; the cost is native config, not Dart. |
| **Email confirmations** | **⚠️ via forwarding, not the share sheet** | Email apps share inconsistently (subject snippet / sometimes a PDF / rarely the full body). The proven pattern is **forward-to-an-address** (TripIt's `plans@tripit.com`) → inbound-email webhook → the same engine. This is **backend infra, not app share registration.** |

### Extraction (the hard part — and the differentiator)
- **Do not template-parse per vendor** (TripIt maintains hundreds of brittle parsers — a permanent tax).
- **Primary: LLM extraction (Claude) in an edge function** with **structured output** → normalized
  `{ trip?, planItems[], expenses[] }` mapped to Vamo's existing taxonomy. Handles the long tail
  (any airline / OTA / hotel / receipt) with **no per-vendor code.** This is Vamo's **first LLM
  dependency** (the app makes zero LLM calls today).
- **Reliability boosters:**
  - Parse **schema.org JSON-LD** first when present (`FlightReservation` / `LodgingReservation` is
    embedded in many confirmation emails; Google/Apple rely on it) — deterministic + cheap; LLM fallback.
  - Feed image shares through the **existing on-device OCR** (`receipt_ocr_*`) before extraction.

### Privacy & security (material — privacy-by-default)
Tickets/emails are heavy PII (names, PNRs, addresses, payment fragments). The content transits the
backend + the LLM. Non-negotiables:
- Explicit user action (they chose to share); **confirm-before-commit** always (never silently create
  or modify a trip).
- **Strip payment data** before extraction; **ephemeral processing** — do not persist raw email/ticket
  past the parse; store only the structured result the user accepts.
- Use a **no-train** LLM endpoint; document retention.
- **Email path auth:** verify the inbound sender maps to a registered Vamo user (or use a per-user
  secret inbound address) so strangers can't inject plans.

### Verdict
Feasible and differentiating, built largely on **reusable pieces** (OCR, the transfer/visit/stay
taxonomy + `metadata` jsonb, expenses, the edge-function pattern, the deep-link intake precedent). The
new surface area is: share-sheet/extension intake, the LLM extraction engine, and (for email) inbound
infra. Biggest risks: email-share unreliability (→ use forwarding), extraction accuracy (→ JSON-LD +
confirm-before-commit), PII handling, and iOS extension setup.

## Architecture — one engine, many mouths
```
[Android share sheet] ─┐
[iOS share extension] ─┼─► normalize to text/asset ─► parse-shared-content (edge fn)
[Forward-to-Vamo email]┘        (OCR / PDF / raw)         │  1. JSON-LD parse (if present)
                                                          │  2. strip payment PII
                                                          │  3. Claude structured output
                                                          ▼
                                          { trip?, planItems[], expenses[] }  (Vamo schema)
                                                          ▼
                                   Import-preview screen (shared Dart, platform-agnostic)
                                   edit · choose "Add to <trip>" or "Create new trip"
                                                          ▼
                            commit via existing repos (plan_repository / expenses_repository / create-trip RPC)
```

**Cross-platform design principle (so iOS is cheap):** only the **intake** is platform-specific
(Android intent-filters now; iOS share extension later). The **edge function, the structured schema,
the import-preview screen, and the commit path are all shared Dart/backend** — both platforms (and the
email path) reuse them verbatim. Build W4.1 with this seam from day one.

## Mapping to the existing model
- **Flights / trains / transfers** → `trip_plan_items` kind `transfer` (or legacy `flight`/`train`) with
  `metadata.subtype` + operator / PNR / from→to / times (the S53 transfer schema).
- **Hotels / stays** → kind `lodging`/`stay` with address + check-in/out in `metadata`.
- **Activities / tours / visits** → kind `activity` / `visit`.
- **Receipts** → `expenses` (reuse OCR + the FX/amount path).
- **Trip shell** (when "create from scratch") → `create_trip` RPC: destination + start/end dates derived
  from the dominant booking; then attach the parsed items.

## Phased roadmap
- **W4.1 — Android share → files/images/text** (P0; highest ROI, lowest risk). Ships the engine + the
  preview/commit flow. See `docs/slices/W4_1_SHARE_IMPORT_PROMPT.md`.
- **W4.2 — iOS share extension.** Native extension target + app group; reuses the engine + preview/commit
  unchanged. The only platform work.
- **W4.3 — Forward-to-Vamo email** (the Lufthansa-email "wow"). Inbound email (Postmark/SendGrid inbound
  or Cloudflare Email Routing) → webhook → same engine → notification "Found a flight to Rome — add it?".
  Per-user secret address / verified-sender.

**Why this order:** W4.1 proves the engine at lowest risk; W4.2 and W4.3 reuse it. Email is the
highest-wow but riskiest (ingestion reliability + inbound infra + sender-auth), so it lands once the
engine is trusted — not first.

## The one decision to greenlight
Adopting an **LLM extraction backend** — Claude API in an edge function: cost-per-parse, an
`ANTHROPIC_API_KEY` secret, and the PII policy above. Everything else is conventional mobile + backend
work. This is the strategic commitment that turns the feature into a moat instead of a fragile parser
farm.

## Open questions
1. LLM cost ceiling per import + a daily/user cap to bound spend?
2. Confidence threshold — auto-fill vs. flag low-confidence fields for the user in the preview?
3. Email: per-user secret address (`u_<id>@in.vamo.world`) vs. sender-matching against verified profile emails?
4. Retention: keep the structured result only, or also a redacted source snippet for "view original"?
5. Which inbound-email provider (Postmark / SendGrid / Cloudflare Email Routing) for W4.3?
