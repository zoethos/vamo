import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Invite token waiting for sign-in (set when a join link opens while logged out).
final pendingInviteTokenProvider = StateProvider<String?>((ref) => null);
