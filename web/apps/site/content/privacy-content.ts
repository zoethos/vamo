// Canonical source: ../../../../docs/legal/PRIVACY.md — keep in sync when policy changes.

export const privacySections = [
  {
    title: "What we collect, and why",
    paragraphs: [
      "**Account**: your email address and a display name — to sign you in and show your name to your trip companions.",
      "**Trip data you create**: trips, expenses, splits, settlements, notes, photos, receipt scans, plan items. Visible **only to the members of that trip** — enforced at the database layer, not just in the interface. Nothing is public unless you explicitly share it (e.g. posting a snapshot card to social media yourself).",
      "**Capture photo metadata**: if you turn on \"Tag captures with location\" in Profile, new trip photos may store location coordinates and original photo time from the image file. This is off by default; when it is off, Vamo does not read that metadata for capture photos. Stored capture metadata is visible only to members of the same trip.",
      "**Receipt details**: when you scan a receipt, text recognition runs **on your device** — the receipt image is stored privately for your trip; what the OCR reads (amount, merchant, place) becomes part of the expense. If a photo contains location metadata (EXIF), we may use it to attach a place to the expense, visible to your trip members like the expense itself.",
      "**Usage analytics**: anonymous-style product events (e.g. \"a trip was created\", \"an error was shown\") to understand what works and what breaks. Analytics events **never contain** your trip contents: no amounts, no receipt text, no addresses or coordinates, no message text, no invite tokens. Analytics are processed in the EU.",
    ],
  },
  {
    title: "What we never do",
    list: [
      "We never sell or rent your data. To anyone.",
      "We never show ads or share data with ad networks.",
      "We never move money — payments happen in the apps you already use.",
      "We never make your trips public. Sharing is always your explicit act.",
    ],
  },
  {
    title: "Who processes data for us",
    list: [
      "**Supabase** — database, authentication, file storage (your trip data).",
      "**PostHog (EU)** — product analytics (sanitized events as described).",
      "**Brevo** — transactional email (sign-in codes and notifications).",
    ],
    footer:
      "Each processes data solely to provide Vamo's functionality.",
  },
  {
    title: "Your rights",
    paragraphs: [
      "You can access, correct, export, or delete your data. Deleting an expense or trip removes it for you per the in-app retention options; deleting your **account** removes your personal data entirely (in-app account deletion is rolling out; meanwhile email privacy@vamo.world and we'll do it promptly). Shared trip data you contributed to others' trips (e.g. an expense in a group ledger) may persist for the other members, attributed minimally.",
      "EU/EEA users: you may also lodge a complaint with your local data protection authority.",
    ],
  },
  {
    title: "Data retention",
    paragraphs: [
      "Trip data persists while the trip exists and per its members' retention choices. Sign-in codes expire within one hour. Invite links expire within 30 days.",
    ],
  },
  {
    title: "Changes",
    paragraphs: [
      "We'll update this page when the policy changes and note the date above. Material changes will be announced in the app.",
    ],
  },
] as const;

export const privacyIntro =
  "Vamo is a trip companion app: split costs, capture moments, share the story. This policy explains what we collect, why, and what we never do. The short version: **your trips are private by default, we don't sell data, and we don't show ads.**";

export const privacyMeta =
  "Last updated: June 2026 · Contact: privacy@vamo.world";
