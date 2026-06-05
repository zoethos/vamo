import 'package:app_core/app_core.dart';

import 'invite_channel.dart';

/// Fires [VamoEvent.memberInvited] on show/share; [VamoEvent.qrShown] when QR displayed.
void captureMemberInvitedShow(
  Analytics analytics, {
  required String tripId,
  required InviteChannel channel,
}) {
  analytics.capture(
    VamoEvent.memberInvited,
    properties: {
      'trip_id': tripId,
      'channel': channel.analyticsValue,
    },
  );
  if (channel == InviteChannel.qr) {
    analytics.capture(
      VamoEvent.qrShown,
      properties: {'trip_id': tripId},
    );
  }
}

void captureInviteAccepted(
  Analytics analytics, {
  required String tripId,
  required InviteChannel channel,
}) {
  analytics.capture(
    VamoEvent.inviteAccepted,
    properties: {
      'trip_id': tripId,
      'channel': channel.analyticsValue,
    },
  );
}
