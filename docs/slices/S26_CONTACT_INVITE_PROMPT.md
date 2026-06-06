# S26 — Contact Invite · growth slice

**Branch:** `feature/contact-invite`
**Estimate:** ~1.5-2 dev-days
**Depends:** S15 invite infra, S21 merged
**Spec gap:** contact-based invites / referral MVP, identified 2026-06-06
**Roadmap position:** Wave-2 growth polish, before/alongside internal-build tester onboarding if time allows. Does not block S22.

## Scope

Let a trip member invite someone from their phone contacts without importing the address book or adding referral-reward infrastructure.

This slice **reuses** the existing invite table, invite token, `/j/<token>` owned-domain join link, and `join_trip` RPC. It adds a contact invite UI path, channel attribution, and native picker/compose helpers only.

Out of scope:

- Referral rewards, invite credits, per-contact attribution, abuse controls.
- Full in-app contact browser, multi-select, contact sync, or matching contacts to Vamo users.
- Persisting or uploading any contact name, phone number, or email address.
- Schema, RPC, RLS, or Supabase migration changes.

## Hard Decisions

### 1. No Address-Book Permission

Do **not** request broad contacts access.

- No `READ_CONTACTS` in Android manifest.
- No `WRITE_CONTACTS`.
- No full contact-list read.
- No contact import/sync.

Reason: current Android and Play policy direction strongly favors privacy-preserving contact pickers over broad contacts permission. The v2 `flutter_contacts` package confirms `showPicker()` is permissionless, but `showPicker(properties: ...)` requires `READ_CONTACTS` on Android. Do not use that Android path.

### 2. Contact Details Are Selected, Not Read

The app may receive only the single phone number or email address the user explicitly selects through an OS picker.

Preferred Android behavior:

- First show a small in-app method sheet: **Text message**, **Email**, **Share link**.
- For Text message, launch a native Android `ACTION_PICK` contact-data picker for `ContactsContract.CommonDataKinds.Phone.CONTENT_TYPE`.
- For Email, launch a native Android `ACTION_PICK` picker for `ContactsContract.CommonDataKinds.Email.CONTENT_TYPE`.
- Read only the returned selected data URI under its temporary grant.

Preferred iOS behavior:

- Use `CNContactPickerViewController` or the plugin equivalent only if it can return selected phone/email details without prompting for full contact permission.
- If iOS provisioning or implementation is not ready, hide the contact action on iOS and leave it Android-first.

Fallback:

- If the picker, contact-data query, SMS/email compose, or platform capability fails, fall back to the existing share sheet with the same `ch=contact` invite URL.

### 3. Use `url_launcher` For Compose

Add `url_launcher` for `sms:` and `mailto:` compose URIs.

- Use `launchUrl` directly and catch failure rather than relying only on `canLaunchUrl`; the package docs note `canLaunchUrl` can be false even when launching may work.
- Add Android `<queries>` entries only for `sms` and `mailto` if needed for capability checks.
- On iOS, add `LSApplicationQueriesSchemes` only if capability checks require them.

### 4. Attribution, Not PII

Add `InviteChannel.contact`.

Invite URLs support `ch=contact`, and unknown/absent channel values default to `link`.

Analytics rules:

- `member_invited`: may include `channel: contact` and `target_type: phone | email | share_fallback`.
- `invite_accepted`: may include `channel: contact`.
- Never log contact name, phone, email, raw URI, invite token, or message body.

## Existing Code Entry Points

Use these existing surfaces:

- `packages/feature_split/lib/src/trips/members_tab.dart`
  - Currently owns `Invite Vamigos`, QR, share sheet, role actions, and hardcoded member copy.
  - Add **Invite from contacts** here and in the Members-tab FAB bottom sheet.
- `packages/feature_split/lib/src/invites/invite_channel.dart`
  - Add `contact('contact')`.
- `packages/app_core/lib/src/invites/invite_urls.dart` or the existing `InviteUrls` location in `app_core`
  - Add channel query support for web/app invite links.
  - Preserve old URL behavior when no channel is passed.
- `packages/feature_split/lib/src/invites/invite_route.dart`
- `packages/feature_split/lib/src/invites/invite_flow.dart`
- `packages/feature_split/lib/src/invites/join_trip_screen.dart`
  - Parse and carry pending invite channel.
  - Unknown or missing `ch` never throws; default to `InviteChannel.link`.
- `packages/feature_split/lib/src/invites/invite_analytics.dart`
  - Extend analytics without PII.
- `packages/feature_split/lib/src/invites/invite_labels.dart`
  - Add all new contact/method/fallback copy.
- `app/lib/split_labels.dart` and `app/lib/l10n/app_en.arb`
  - Wire ARB labels. Move touched hardcoded Members-tab invite strings into ARB.

## Implementation Shape

Create a small invite-contact abstraction so tests do not depend on platform channels:

- `contact_invite_picker.dart`
  - conditional export:
    - mobile implementation
    - web/unsupported stub
- `ContactInviteTarget`
  - `targetType: phone | email`
  - `value`
  - optional display label for local UI only
- `ContactInviteGateway`
  - `bool get isSupported`
  - `Future<ContactInviteTarget?> pickPhoneTarget()`
  - `Future<ContactInviteTarget?> pickEmailTarget()`
  - `Future<bool> composeSms({required String phone, required String body})`
  - `Future<bool> composeEmail({required String email, required String subject, required String body})`

Privacy rule: `ContactInviteTarget.value` exists only in memory long enough to launch compose. Do not persist it, enqueue it, or put it in analytics.

Android implementation can be a tiny platform-channel wrapper if existing packages cannot do a permissionless selected phone/email pick. Do not add `READ_CONTACTS` to make `flutter_contacts` easier.

## UX Contract

Members tab:

- Existing share link and QR remain.
- Add **Invite from contacts** on supported mobile only.
- Web/unsupported: action is hidden.
- The main Members FAB sheet shows:
  - Invite Vamigos / Share a join link
  - Invite from contacts
  - Show QR

Contact invite flow:

1. Start FlowTracker `invite`.
2. Reuse or create invite token through `getOrCreateInviteToken(tripId)`.
3. Build invite copy with a URL carrying `ch=contact`.
4. Show method sheet:
   - Text message
   - Email
   - Share link
5. If Text message:
   - Pick one phone detail.
   - Open SMS composer.
   - If either fails, share-sheet fallback.
6. If Email:
   - Pick one email detail.
   - Open email composer.
   - If either fails, share-sheet fallback.
7. If Share link or fallback:
   - Use existing `Share.share` path with `channel: contact`, `target_type: share_fallback`.

Copy tone:

- Use Vamigos.
- Do not explain privacy mechanics in the app unless an error/fallback needs a short, useful message.

## Dependencies

Add to `packages/feature_split/pubspec.yaml`:

- `url_launcher: ^6.3.2`

Optional only if the implementation uses it on iOS or for non-Android picker support:

- `flutter_contacts: ^2.2.1`

Add both chosen packages to `docs/DEPENDENCIES.md` key packages:

- `url_launcher`: compose SMS/email; lock-in Low.
- `flutter_contacts` only if actually added: native contact picker helper; lock-in Medium-Low; note Android property picker limitation and no broad contacts permission.

Do not add `READ_CONTACTS` / `WRITE_CONTACTS` as a dependency shortcut.

## Verification

Unit:

- Invite URL with `InviteChannel.contact` includes `ch=contact`.
- Missing/unknown `ch` defaults to `link`.
- `InviteChannel.contact.analyticsValue == 'contact'`.
- Invite analytics includes only channel + coarse `target_type`; no token/contact fields.

Widget:

- Contact action present when `ContactInviteGateway.isSupported == true`.
- Contact action absent when unsupported/web.
- Method sheet has Text message, Email, Share link.
- Phone target opens SMS compose with `ch=contact`.
- Email target opens email compose with `ch=contact`.
- Picker failure falls back to share sheet.
- Compose failure falls back to share sheet.
- No usable / cancelled pick exits safely without fake analytics success.
- Touched Members-tab strings are ARB-backed.

Manual Android:

1. Open trip -> Members.
2. Tap Invite from contacts.
3. Text message path opens phone-detail picker.
4. Selecting a contact opens SMS composer with invite copy and `https://vamo.world/j/<token>?ch=contact` or equivalent channel-bearing URL.
5. Email path opens email-detail picker/composer if device has email-capable contacts/app.
6. Cancel picker: no crash, no fake invite success.
7. Recipient opens link and joins; `invite_accepted { channel: contact }`.
8. Existing Share link and QR paths still work.

`melos run ci` green. No cloud smoke needed because there is no DB change.

## Reviewer Checklist

- [ ] No broad contacts permission in Android manifest or iOS Info.plist.
- [ ] No contact list read/import/sync.
- [ ] Android does not use `FlutterContacts.native.showPicker(properties: ...)` because that requires `READ_CONTACTS`.
- [ ] Contact phone/email exists only transiently in memory for compose.
- [ ] No contact PII or token in analytics/logs/outbox.
- [ ] `InviteChannel.contact` and `ch=contact` round-trip; unknown/missing channel defaults to link.
- [ ] Existing link + QR invite flows unchanged.
- [ ] Contact action hidden on unsupported platforms.
- [ ] Failures fall back to share sheet or exit safely; no silent fake success.
- [ ] ARB coverage for new/touched strings.

## Later Epic

Referral rewards, per-contact attribution, invite credits, multi-select, address-book matching, and abuse controls are W3+ and require backend/product design.
