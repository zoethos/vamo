import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'notification_labels.dart';
import 'notification_models.dart';
import 'notifications_providers.dart';
import 'notifications_repository.dart';

class NotificationsInboxScreen extends ConsumerWidget {
  const NotificationsInboxScreen({super.key, required this.labels});

  final NotificationLabels labels;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(notificationsProvider);
    final colors = context.vamoColors;
    final type = context.vamoType;

    return Scaffold(
      appBar: AppBar(
        title: Text(labels.inboxTitle),
        actions: [
          notifications.maybeWhen(
            data: (items) {
              final hasUnread = items.any((n) => n.isUnread);
              if (!hasUnread) return const SizedBox.shrink();
              return TextButton(
                onPressed: () async {
                  await ref
                      .read(notificationsRepositoryProvider)
                      .markAllRead();
                },
                child: Text(labels.markAllRead),
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: notifications.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => AppErrorState(
          screen: 'notifications',
          message: labels.emptySubtitle,
          onRetry: () => ref.invalidate(notificationsProvider),
        ),
        data: (items) {
          if (items.isEmpty) {
            return AppEmptyState(
              screen: 'notifications',
              icon: Icons.notifications_outlined,
              title: labels.emptyTitle,
              subtitle: labels.emptySubtitle,
            );
          }
          return ListView.separated(
            padding: EdgeInsetsDirectional.all(context.vamoSpace.x4),
            itemCount: items.length,
            separatorBuilder: (_, __) =>
                SizedBox(height: context.vamoSpace.x2),
            itemBuilder: (context, index) {
              final item = items[index];
              return _NotificationRow(
                item: item,
                labels: labels,
                colors: colors,
                typeStyle: type,
                onTap: () => _openNotification(context, ref, item),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _openNotification(
    BuildContext context,
    WidgetRef ref,
    NotificationItem item,
  ) async {
    if (item.isUnread) {
      await ref.read(notificationsRepositoryProvider).markRead(item.id);
    }
    final route = item.route;
    if (route != null && route.isNotEmpty && context.mounted) {
      context.push(route);
    }
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({
    required this.item,
    required this.labels,
    required this.colors,
    required this.typeStyle,
    required this.onTap,
  });

  final NotificationItem item;
  final NotificationLabels labels;
  final VamoSemanticColors colors;
  final VamoTypeScale typeStyle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = _iconForType(item.type);
    final typeLabel = _typeLabel(item.type, labels);

    return Semantics(
      button: true,
      label: '${item.title}. ${item.body}. $typeLabel',
      child: Material(
        color: item.isUnread ? colors.surface : colors.background,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsetsDirectional.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                VamoCircleIcon(
                  diameter: 44,
                  backgroundColor: colors.surface,
                  shadow: false,
                  child: Icon(icon, color: colors.primary, size: 22),
                ),
                SizedBox(width: context.vamoSpace.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.title,
                              style: typeStyle.titleSmall.copyWith(
                                color: colors.onBackground,
                                fontWeight: item.isUnread
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (item.isUnread)
                            Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsetsDirectional.only(
                                start: 8,
                              ),
                              decoration: BoxDecoration(
                                color: colors.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      SizedBox(height: context.vamoSpace.x1),
                      Text(
                        item.body,
                        style: typeStyle.bodyMedium.copyWith(
                          color: colors.secondary,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: context.vamoSpace.x2),
                      Text(
                        formatRelativeTime(item.createdAt),
                        style: typeStyle.labelSmall.copyWith(
                          color: colors.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _iconForType(String type) {
    return switch (type) {
      'close_notice' => Icons.notifications_active_outlined,
      'close_reminder' => Icons.schedule_outlined,
      'deemed_closed' => Icons.lock_outline,
      'settle_nudge' => Icons.payments_outlined,
      _ => Icons.notifications_outlined,
    };
  }

  String _typeLabel(String type, NotificationLabels labels) {
    return switch (type) {
      'close_notice' => labels.typeCloseNotice,
      'close_reminder' => labels.typeCloseReminder,
      'deemed_closed' => labels.typeDeemedClosed,
      'settle_nudge' => labels.typeSettleNudge,
      _ => labels.typeGeneric,
    };
  }
}
