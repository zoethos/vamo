import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../trips/trips_providers.dart';
import 'invite_channel.dart';
import 'invites_repository.dart';
import 'pending_invite.dart';

/// After sign-in, join a trip if [pendingInviteTokenProvider] was set.
Future<void> tryConsumePendingInvite({
  required WidgetRef ref,
  required BuildContext context,
}) async {
  final token = ref.read(pendingInviteTokenProvider);
  if (token == null || token.isEmpty) return;
  if (!ref.read(isSignedInProvider)) return;

  final channel = ref.read(pendingInviteChannelProvider) ?? InviteChannel.link;

  ref.read(pendingInviteTokenProvider.notifier).state = null;
  ref.read(pendingInviteChannelProvider.notifier).state = null;

  try {
    final tripId = await ref
        .read(invitesRepositoryProvider)
        .joinTrip(token, channel: channel);
    ref.invalidate(tripsSyncProvider);
    await ref.read(syncCoordinatorProvider).syncNow();
    if (context.mounted) {
      context.go(AppRoutes.trip(tripId));
    }
  } catch (e) {
    if (context.mounted) {
      showActionError(
        context,
        ref,
        screen: 'join',
        action: 'join_trip',
        error: e,
      );
    }
  }
}

/// Reads invite channel from join-route query (`ch`); defaults to [InviteChannel.link].
InviteChannel inviteChannelFromQuery(Map<String, String> query) =>
    InviteChannel.fromQuery(query['ch']);

/// Reads invite token from `/join` or `/join/:token` routes.
String? inviteTokenFromLocation(
  String location, {
  Map<String, String> query = const {},
}) {
  final q = query['token'];
  if (q != null && q.isNotEmpty) return q;

  final match = RegExp(r'^/join/([^/?#]+)').firstMatch(location);
  if (match != null) {
    return Uri.decodeComponent(match.group(1)!);
  }
  return null;
}
