import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'invite_channel.dart';

/// Invite token waiting for sign-in (set when a join link opens while logged out).
final pendingInviteTokenProvider = StateProvider<String?>((ref) => null);

/// How the pending token arrived (`qr` scan vs `link` deep link).
final pendingInviteChannelProvider = StateProvider<InviteChannel?>((ref) => null);
