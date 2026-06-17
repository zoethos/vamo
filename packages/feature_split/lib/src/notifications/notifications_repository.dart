import 'package:app_core/app_core.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'notification_models.dart';

final notificationsRepositoryProvider = Provider<NotificationsRepository>((ref) {
  return NotificationsRepository(
    db: ref.watch(appDatabaseProvider),
    client: ref.watch(supabaseClientProvider),
  );
});

class NotificationsRepository {
  NotificationsRepository({
    required AppDatabase db,
    required SupabaseClient client,
  })  : _db = db,
        _client = client;

  final AppDatabase _db;
  final SupabaseClient _client;

  Stream<List<NotificationItem>> watchNotifications() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return Stream.value(const []);
    }
    return _db.watchNotifications(userId).map(
          (rows) => rows.map(NotificationItem.fromLocal).toList(),
        );
  }

  Stream<int> watchUnreadCount() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return Stream.value(0);
    }
    return _db.watchUnreadNotificationCount(userId);
  }

  Future<void> syncFromRemote() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    final rows = await _client
        .from('notifications')
        .select(
          'id, user_id, trip_id, type, title, body, route, created_at, read_at',
        )
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    final remoteIds = <String>{};
    for (final row in (rows as List).cast<Map<String, dynamic>>()) {
      final id = row['id'] as String;
      remoteIds.add(id);
      await _db.upsertNotification(
        LocalNotificationsCompanion(
          id: Value(id),
          userId: Value(row['user_id'] as String),
          tripId: Value(row['trip_id'] as String?),
          type: Value(row['type'] as String),
          title: Value(row['title'] as String),
          body: Value(row['body'] as String),
          route: Value(row['route'] as String?),
          createdAt: Value(DateTime.parse(row['created_at'] as String)),
          readAt: Value(_ts(row['read_at'])),
        ),
      );
    }
    await _db.pruneNotifications(remoteIds);
  }

  Future<void> markRead(String id) async {
    await _client.rpc('mark_notification_read', params: {'p_id': id});
    await _db.markNotificationReadLocal(id);
  }

  Future<void> markAllRead() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    await _client.rpc('mark_all_notifications_read');
    await _db.markAllNotificationsReadLocal(userId);
  }

  DateTime? _ts(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value.toUtc();
    return DateTime.tryParse(value as String)?.toUtc();
  }
}
