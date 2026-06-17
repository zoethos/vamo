import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'notification_models.dart';
import 'notifications_repository.dart';

final notificationsProvider = StreamProvider<List<NotificationItem>>((ref) {
  return ref.watch(notificationsRepositoryProvider).watchNotifications();
});

final unreadNotificationCountProvider = StreamProvider<int>((ref) {
  return ref.watch(notificationsRepositoryProvider).watchUnreadCount();
});
