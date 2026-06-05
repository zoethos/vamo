import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'activity_models.dart';
import 'activity_repository.dart';

class ActivityScreenLabels {
  const ActivityScreenLabels({
    required this.title,
    required this.emptyTitle,
    required this.emptySubtitle,
    required this.loadError,
  });

  final String title;
  final String emptyTitle;
  final String emptySubtitle;
  final String loadError;
}

/// Cross-trip chronological feed from local Drift data (v1).
class ActivityScreen extends ConsumerWidget {
  const ActivityScreen({super.key, required this.labels});

  final ActivityScreenLabels labels;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(activityFeedProvider);

    return Scaffold(
      appBar: AppBar(title: Text(labels.title)),
      body: feed.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AppErrorState(
          screen: 'activity',
          message: labels.loadError,
          onRetry: () => ref.invalidate(activityFeedProvider),
        ),
        data: (items) {
          if (items.isEmpty) {
            return AppEmptyState(
              screen: 'activity',
              icon: Icons.timeline_outlined,
              title: labels.emptyTitle,
              subtitle: labels.emptySubtitle,
            );
          }
          final grouped = groupActivityByDay(items);
          final days = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

          return ListView.builder(
            padding: const EdgeInsetsDirectional.all(16),
            itemCount: days.length,
            itemBuilder: (context, i) {
              final day = days[i];
              final dayItems = grouped[day]!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (i > 0) const SizedBox(height: 16),
                  Text(
                    DateFormat.yMMMd().format(day.toLocal()),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: AppColors.graphite,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 8),
                  ...dayItems.map((item) => _ActivityTile(item: item)),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.item});

  final ActivityItem item;

  IconData get _icon => switch (item.kind) {
        ActivityKind.expense => Icons.receipt_outlined,
        ActivityKind.settlement => Icons.handshake_outlined,
        ActivityKind.memberJoined => Icons.person_add_outlined,
      };

  Color get _chipColor => switch (item.kind) {
        ActivityKind.expense => AppColors.jadeTeal,
        ActivityKind.settlement => AppColors.goLime,
        ActivityKind.memberJoined => AppColors.blush,
      };

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsetsDirectional.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _chipColor.withValues(alpha: 0.25),
          child: Icon(_icon, color: AppColors.ink, size: 20),
        ),
        title: Text(item.title),
        subtitle: Text('${item.tripName} · ${item.subtitle}'),
        trailing: Text(
          DateFormat.Hm().format(item.occurredAt.toLocal()),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.graphite,
              ),
        ),
      ),
    );
  }
}
