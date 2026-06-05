import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'invite_channel.dart';
import 'pending_invite.dart';

/// Routes a parsed invite token through the existing join flow.
void routeInviteToken({
  required BuildContext context,
  required WidgetRef ref,
  required String token,
  required InviteChannel channel,
}) {
  ref.read(pendingInviteChannelProvider.notifier).state = channel;
  if (ref.read(isSignedInProvider)) {
    context.go(InviteUrls.inAppJoinLocation(token));
    return;
  }
  ref.read(pendingInviteTokenProvider.notifier).state = token;
  context.go(AppRoutes.auth);
}
