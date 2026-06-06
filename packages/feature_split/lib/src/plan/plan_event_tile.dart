import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'event_rsvp_models.dart';
import 'plan_event_rsvp_chips.dart';
import 'plan_labels.dart';

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
        : labels.rsvpSummary(
            view.counts.going,
            view.counts.maybe,
            view.counts.declined,
          );

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
                      Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Chip(
                            label: Text(labels.kindLabel(item.kind)),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                          Text(
                            item.title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                      if (dateLabel != null)
                        Text(
                          dateLabel,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
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
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
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
                      PopupMenuItem(
                          value: 'edit', child: Text(labels.editItem)),
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
              PlanEventRsvpChips(
                planItemId: item.id,
                labels: labels,
                myStatus: view.myStatus,
                readOnly: false,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
