import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'event_rsvp_models.dart';
import 'plan_labels.dart';
import 'plan_repository.dart';

class PlanEventTile extends ConsumerWidget {
  const PlanEventTile({
    super.key,
    required this.tripId,
    required this.view,
    required this.labels,
    required this.readOnly,
    required this.onEdit,
    required this.onDelete,
  });

  final String tripId;
  final PlanItemEventView view;
  final PlanTabLabels labels;
  final bool readOnly;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = view.item;
    final dateLabel = item.startsAt == null
        ? null
        : DateFormat.yMMMd().format(item.startsAt!.toLocal());
    final placeLabel = item.notes?.trim();
    final summary = view.counts.isEmpty
        ? null
        : labels.rsvpSummary(view.counts.going, view.counts.maybe);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  item.kind.icon,
                  color: AppColors.jadeTeal,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (dateLabel != null)
                        Text(
                          dateLabel,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppColors.graphite,
                              ),
                        ),
                      if (placeLabel != null && placeLabel.isNotEmpty)
                        Text(
                          placeLabel,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      if (summary != null)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(top: 4),
                          child: Text(
                            summary,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: AppColors.graphite,
                                ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (!readOnly)
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'edit') onEdit();
                      if (v == 'delete') onDelete();
                    },
                    itemBuilder: (ctx) => [
                      PopupMenuItem(value: 'edit', child: Text(labels.editItem)),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(labels.deleteItem),
                      ),
                    ],
                  ),
              ],
            ),
            if (!readOnly) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final status in EventRsvpStatus.values)
                    ChoiceChip(
                      label: Text(_statusLabel(status)),
                      selected: view.myStatus == status,
                      onSelected: (_) {
                        if (view.myStatus == status) {
                          _clearStatus(ref);
                        } else {
                          _setStatus(ref, status);
                        }
                      },
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _statusLabel(EventRsvpStatus status) => switch (status) {
        EventRsvpStatus.going => labels.rsvpGoing,
        EventRsvpStatus.maybe => labels.rsvpMaybe,
        EventRsvpStatus.declined => labels.rsvpDeclined,
      };

  Future<void> _setStatus(WidgetRef ref, EventRsvpStatus status) async {
    await ref.read(planRepositoryProvider).setEventRsvp(
          planItemId: view.item.id,
          status: status,
        );
  }

  Future<void> _clearStatus(WidgetRef ref) async {
    await ref.read(planRepositoryProvider).clearEventRsvp(
          planItemId: view.item.id,
        );
  }
}
