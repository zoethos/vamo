/// Localized copy for QR invite surfaces (R9).
class InviteLabels {
  const InviteLabels({
    required this.showQr,
    required this.scanQr,
    required this.qrCaption,
    required this.notVamoInvite,
    required this.cameraDenied,
    required this.pasteLink,
    required this.pasteHint,
    required this.pasteJoin,
    required this.scannerTitle,
    required this.inviteVamigos,
    required this.inviteAction,
    required this.shareJoinLink,
    required this.inviteFromContacts,
    required this.contactMethodTextMessage,
    required this.contactMethodEmail,
    required this.contactMethodShareLink,
    required this.contactInviteSubject,
    required this.contactInviteBody,
    required this.membersVamigosTitle,
    required this.membersInviteHintSolo,
    required this.membersShareFootnote,
    required this.membersCountOnTrip,
  });

  final String showQr;
  final String scanQr;
  final String qrCaption;
  final String notVamoInvite;
  final String cameraDenied;
  final String pasteLink;
  final String pasteHint;
  final String pasteJoin;
  final String scannerTitle;
  final String inviteVamigos;
  final String inviteAction;
  final String shareJoinLink;
  final String inviteFromContacts;
  final String contactMethodTextMessage;
  final String contactMethodEmail;
  final String contactMethodShareLink;
  final String contactInviteSubject;
  final String Function(String webUrl, String appUri) contactInviteBody;
  final String membersVamigosTitle;
  final String membersInviteHintSolo;
  final String membersShareFootnote;
  final String Function(int count) membersCountOnTrip;
}
