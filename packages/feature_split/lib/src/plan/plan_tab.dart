import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'event_rsvp_models.dart';
import 'plan_event_tile.dart';
import 'plan_item_sheet.dart';
import 'plan_labels.dart';
import 'plan_models.dart';
import 'plan_providers.dart';
import 'plan_repository.dart';

class PlanTab extends ConsumerStatefulWidget {
  const PlanTab({
    super.key,
    required this.tripId,
    required this.labels,
    required this.readOnly,
  });

  final String tripId;
  final PlanTabLabels labels;
  final bool readOnly;

  @override
  ConsumerState<PlanTab> createState() => PlanTabState();
}

class PlanTabState extends ConsumerState<PlanTab> {
  /// Opens the add-plan-item sheet (used by trip-home FAB on the Plan tab).
  void openAddPlanItem() => _openSheet(context, null);
  final _listNameController = TextEditingController();
  final _listItemController = TextEditingController();

  @override
  void dispose() {
    _listNameController.dispose();
    _listItemController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final plans = ref.watch(tripPlanItemsProvider(widget.tripId));
    final lists = ref.watch(tripListItemsProvider(widget.tripId));
    final eventViews = ref.watch(tripPlanEventViewsProvider(widget.tripId));
    final repo = ref.read(planRepositoryProvider);

    return plans.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => AppErrorState(
        screen: 'trip_plan',
        message: widget.labels.loadError,
        onRetry: () => ref.invalidate(tripPlanItemsProvider(widget.tripId)),
      ),
      data: (planItems) {
        return lists.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => AppErrorState(
            screen: 'trip_plan',
            message: widget.labels.checklistsLoadError,
            onRetry: () => ref.invalidate(tripListItemsProvider(widget.tripId)),
          ),
          data: (listItems) {
            final grouped = groupPlanItemsByDay(planItems);
            final checklists = groupListItemsByName(listItems);

            if (planItems.isEmpty && listItems.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AppEmptyState(
                      screen: 'trip_plan',
                      icon: Icons.view_kanban_outlined,
                      title: widget.labels.emptyTitle,
                      subtitle: widget.labels.emptySubtitle,
                    ),
                    if (!widget.readOnly) ...[
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => _openSheet(context, null),
                        icon: const Icon(Icons.add),
                        label: Text(widget.labels.addPlanItem),
                      ),
                    ],
                  ],
                ),
              );
            }

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (!widget.readOnly)
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton.icon(
                      onPressed: () => _openSheet(context, null),
                      icon: const Icon(Icons.add),
                      label: Text(widget.labels.addPlanItem),
                    ),
                  ),
                for (final section in grouped) ...[
                  Text(
                    section.dayKey ?? widget.labels.undatedSection,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.graphite,
                        ),
                  ),
                  const SizedBox(height: 8),
                  ...section.items.map(
                    (item) {
                      if (item.kind == PlanItemKind.activity) {
                        final view = eventViews[item.id];
                        return PlanEventTile(
                          tripId: widget.tripId,
                          view: view ??
                              PlanItemEventView(
                                item: item,
                                counts: const EventRsvpCounts(),
                                myStatus: null,
                              ),
                          labels: widget.labels,
                          readOnly: widget.readOnly,
                          onEdit: () => _openSheet(context, item),
                          onDelete: () => repo.deletePlanItem(item.id),
                        );
                      }
                      return _PlanItemTile(
                        item: item,
                        labels: widget.labels,
                        readOnly: widget.readOnly,
                        onEdit: () => _openSheet(context, item),
                        onDelete: () => repo.deletePlanItem(item.id),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                ],
                Text(
                  widget.labels.checklistsSection,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                for (final entry in checklists.entries) ...[
                  Text(entry.key,
                      style: Theme.of(context).textTheme.labelLarge),
                  ...entry.value.map(
                    (item) => CheckboxListTile(
                      value: item.isChecked,
                      onChanged: widget.readOnly
                          ? null
                          : (_) => repo.toggleListItem(item.id),
                      title: Text(item.label),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (!widget.readOnly) ...[
                  TextField(
                    controller: _listNameController,
                    decoration: InputDecoration(
                      labelText: widget.labels.defaultListName,
                      hintText: widget.labels.defaultListName,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _listItemController,
                          decoration: InputDecoration(
                            hintText: widget.labels.addListItemHint,
                          ),
                          onSubmitted: (_) => _addListItem(repo),
                        ),
                      ),
                      IconButton(
                        onPressed: () => _addListItem(repo),
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _addListItem(PlanRepository repo) async {
    final listName = _listNameController.text.trim().isEmpty
        ? widget.labels.defaultListName
        : _listNameController.text.trim();
    final label = _listItemController.text.trim();
    if (label.isEmpty) return;
    await repo.addListItem(
      tripId: widget.tripId,
      listName: listName,
      label: label,
    );
    _listItemController.clear();
    if (_listNameController.text.isEmpty) {
      _listNameController.text = listName;
    }
  }

  Future<void> _openSheet(BuildContext context, PlanItemSummary? existing) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => PlanItemSheet(
        tripId: widget.tripId,
        labels: widget.labels,
        existing: existing,
        readOnly: widget.readOnly,
        onSave: (input) async {
          if (existing == null) {
            await ref.read(planRepositoryProvider).addPlanItem(input);
          } else {
            await ref.read(planRepositoryProvider).updatePlanItem(
                  id: existing.id,
                  kind: input.kind,
                  title: input.title,
                  notes: input.notes,
                  startsAt: input.startsAt,
                  endsAt: input.endsAt,
                );
          }
        },
      ),
    );
  }
}

class _PlanItemTile extends StatelessWidget {
  const _PlanItemTile({
    required this.item,
    required this.labels,
    required this.readOnly,
    required this.onEdit,
    required this.onDelete,
  });

  final PlanItemSummary item;
  final PlanTabLabels labels;
  final bool readOnly;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(item.kind.icon, color: AppColors.jadeTeal),
        title: Text(item.title),
        subtitle: item.notes == null || item.notes!.isEmpty
            ? null
            : Text(item.notes!),
        trailing: readOnly
            ? null
            : PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'edit') onEdit();
                  if (v == 'delete') onDelete();
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem(value: 'edit', child: Text(labels.editItem)),
                  PopupMenuItem(value: 'delete', child: Text(labels.deleteItem)),
                ],
              ),
        onTap: readOnly ? null : onEdit,
      ),
    );
  }
}
