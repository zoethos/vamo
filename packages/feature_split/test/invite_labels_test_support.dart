import 'package:feature_split/src/invites/invite_labels.dart';

const testInviteLabels = InviteLabels(
  showQr: 'Show QR',
  scanQr: 'Scan a Vamo QR',
  qrCaption: 'Point a camera at this to join',
  notVamoInvite: "That's not a Vamo invite",
  cameraDenied: 'Camera denied',
  pasteLink: 'Paste invite link',
  pasteHint: 'https://vamo.world/j/…',
  pasteJoin: 'Join from link',
  scannerTitle: 'Scan invite QR',
  inviteVamigos: 'Invite Vamigos',
  shareJoinLink: 'Share a join link',
  inviteFromContacts: 'Invite from contacts',
  contactMethodTextMessage: 'Text message',
  contactMethodEmail: 'Email',
  contactMethodShareLink: 'Share link',
  contactInviteSubject: 'Join my Vamo trip',
  contactInviteBody: _contactInviteBody,
  membersVamigosTitle: 'Vamigos',
  membersInviteHintSolo: 'Invite friends — balances unlock at 2+ people.',
  membersShareFootnote:
      'Share a link — they can join mid-trip. Opens Vamo or the store.',
  membersCountOnTrip: _membersCountOnTrip,
);

String _contactInviteBody(String webUrl, String appUri) =>
    'Join my trip on Vamo!\n$webUrl\n\nHave the app? Tap: $appUri';

String _membersCountOnTrip(int count) => '$count on this trip';
