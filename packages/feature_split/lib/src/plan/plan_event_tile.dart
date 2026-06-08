import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../shared/vamo_slidable_row.dart';
import 'event_rsvp_models.dart';
import 'plan_event_rsvp_picker.dart';
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
    final colors = context.vamoColors;
    final item = view.item;
    final dateLabel = item.startsAt == null
        ? null
        : DateFormat.yMMMd().format(item.startsAt!.toLocal());
    final placeLabel = item.notes?.trim();

    final card = Card(
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
                  color: colors.secondary,
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
                                    color: colors.onSurfaceMuted,
                                  ),
                        ),
                      if (placeLabel != null && placeLabel.isNotEmpty)
                        Text(
                          placeLabel,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      if (!view.counts.isEmpty)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(top: 4),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              if (view.counts.going > 0)
                                _RsvpCountPill(
                                  count: view.counts.going,
                                  label: labels.rsvpGoing,
                                  foreground: colors.onSurface,
                                  background: colors.secondary
                                      .withValues(alpha: 0.18),
                                ),
                              if (view.counts.maybe > 0)
                                _RsvpCountPill(
                                  count: view.counts.maybe,
                                  label: labels.rsvpMaybe,
                                  foreground: colors.onSurfaceMuted,
                                  background: colors.surfaceMuted,
                                ),
                              if (view.counts.declined > 0)
                                _RsvpCountPill(
                                  count: view.counts.declined,
                                  label: labels.rsvpDeclined,
                                  foreground: colors.error,
                                  background: colors.error
                                      .withValues(alpha: 0.12),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                if (!readOnly)
                  PlanEventRsvpControl(
                    planItemId: item.id,
                    labels: labels,
                    myStatus: view.myStatus,
                  ),
              ],
            ),
          ],
        ),
      ),
    );

    if (readOnly) return card;

    return VamoSlidableRow(
      editLabel: labels.editItem,
      deleteLabel: labels.deleteItem,
      deleteConfirmTitle: labels.deleteConfirmTitle,
      deleteConfirmAction: labels.deleteItem,
      cancelLabel: labels.cancelLabel,
      onEdit: onEdit,
      onDelete: onDelete,
      child: card,
    );
  }
}

class _RsvpCountPill extends StatelessWidget {
  const _RsvpCountPill({
    required this.count,
    required this.label,
    required this.foreground,
    required this.background,
  });

  final int count;
  final String label;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: 8,
          vertical: 3,
        ),
        child: Text(
          '$count $label',
          maxLines: 1,
          softWrap: false,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
    );
  }
}
