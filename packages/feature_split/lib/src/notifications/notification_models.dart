import 'package:app_core/app_core.dart';

class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.userId,
    required this.tripId,
    required this.type,
    required this.title,
    required this.body,
    required this.route,
    required this.createdAt,
    required this.readAt,
  });

  final String id;
  final String userId;
  final String? tripId;
  final String type;
  final String title;
  final String body;
  final String? route;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isUnread => readAt == null;

  factory NotificationItem.fromLocal(LocalNotification row) {
    return NotificationItem(
      id: row.id,
      userId: row.userId,
      tripId: row.tripId,
      type: row.type,
      title: row.title,
      body: row.body,
      route: row.route,
      createdAt: row.createdAt,
      readAt: row.readAt,
    );
  }
}
