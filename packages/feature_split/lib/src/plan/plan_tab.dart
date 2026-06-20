import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/vamo_slidable_row.dart';
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
    this.showInlineAddAction = false,
  });

  final String tripId;
  final PlanTabLabels labels;
  final bool readOnly;

  /// Legacy inline add controls — S38 uses header "+" + add menu instead.
  final bool showInlineAddAction;

  @override
  ConsumerState<PlanTab> createState() => PlanTabState();
}

class PlanTabState extends ConsumerState<PlanTab> {
  void openAddPlanItem() => _openSheet(context, null);

  /// Header "+" — choose event/plan item or checklist item.
  Future<void> openAddMenu() async {
    if (widget.readOnly) return;
    final choice = await showModalBottomSheet<_PlanAddChoice>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.event_outlined),
              title: Text(widget.labels.addPlanItem),
              onTap: () => Navigator.pop(ctx, _PlanAddChoice.planItem),
            ),
            ListTile(
              leading: const Icon(Icons.checklist_outlined),
              title: Text(widget.labels.addChecklistItem),
              onTap: () => Navigator.pop(ctx, _PlanAddChoice.checklistItem),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case _PlanAddChoice.planItem:
        await _openSheet(context, null);
      case _PlanAddChoice.checklistItem:
        await _openAddChecklistSheet();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vamoColors;
    final type = context.vamoType;
    final space = context.vamoSpace;
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
                child: AppEmptyState(
                  screen: 'trip_plan',
                  icon: Icons.view_kanban_outlined,
                  title: widget.labels.emptyTitle,
                  subtitle: widget.labels.emptySubtitle,
                ),
              );
            }

            return ListView(
              padding: EdgeInsets.all(space.x4),
              children: [
                if (!widget.readOnly && widget.showInlineAddAction)
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
                    style: type.titleSmall.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.onSurfaceMuted,
                    ),
                  ),
                  SizedBox(height: space.x2),
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
                  SizedBox(height: space.x4),
                ],
                if (checklists.isNotEmpty) ...[
                  Text(
                    widget.labels.checklistsSection,
                    style: type.titleSmall.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.onSurface,
                    ),
                  ),
                  SizedBox(height: space.x2),
                  for (final entry in checklists.entries)
                    _ChecklistSection(
                      listName: entry.key,
                      items: entry.value,
                      readOnly: widget.readOnly,
                      onToggle: (id) => repo.toggleListItem(id),
                    ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _openAddChecklistSheet() async {
    final listNameController = TextEditingController(
      text: widget.labels.defaultListName,
    );
    final itemController = TextEditingController();
    final repo = ref.read(planRepositoryProvider);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final colors = ctx.vamoColors;
        final space = ctx.vamoSpace;
        return Padding(
          padding: EdgeInsetsDirectional.only(
            start: space.x4,
            end: space.x4,
            bottom: MediaQuery.viewInsetsOf(ctx).bottom + space.x4,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.labels.addChecklistItem,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              SizedBox(height: space.x3),
              TextField(
                controller: listNameController,
                decoration: InputDecoration(
                  labelText: widget.labels.defaultListName,
                ),
              ),
              SizedBox(height: space.x2),
              TextField(
                controller: itemController,
                decoration: InputDecoration(
                  labelText: widget.labels.addListItemHint,
                ),
                textInputAction: TextInputAction.done,
              ),
              SizedBox(height: space.x3),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: colors.secondary,
                  foregroundColor: colors.onSecondary,
                ),
                onPressed: () async {
                  final listName = listNameController.text.trim().isEmpty
                      ? widget.labels.defaultListName
                      : listNameController.text.trim();
                  final label = itemController.text.trim();
                  if (label.isEmpty) return;
                  await repo.addListItem(
                    tripId: widget.tripId,
                    listName: listName,
                    label: label,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: Text(widget.labels.save),
              ),
            ],
          ),
        );
      },
    );

    listNameController.dispose();
    itemController.dispose();
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
                  metadata: input.metadata,
                );
          }
        },
      ),
    );
  }
}

enum _PlanAddChoice { planItem, checklistItem }

class _ChecklistSection extends StatelessWidget {
  const _ChecklistSection({
    required this.listName,
    required this.items,
    required this.readOnly,
    required this.onToggle,
  });

  final String listName;
  final List<TripListItemSummary> items;
  final bool readOnly;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = context.vamoColors;
    final type = context.vamoType;
    final space = context.vamoSpace;
    final radius = context.vamoShape;

    return Card(
      margin: EdgeInsetsDirectional.only(bottom: space.x3),
      color: colors.surfaceMuted,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: radius.cardBorderRadius,
        side: BorderSide(color: colors.onSurfaceMuted.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(
          space.x2,
          space.x2,
          space.x2,
          space.x1,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              listName,
              style: type.labelLarge.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.onSurface,
              ),
            ),
            SizedBox(height: space.x1),
            for (final item in items)
              CheckboxListTile(
                value: item.isChecked,
                onChanged: readOnly ? null : (_) => onToggle(item.id),
                title: Text(
                  item.label,
                  style: type.bodyMedium.copyWith(color: colors.onSurface),
                ),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsetsDirectional.zero,
                dense: true,
                shape: RoundedRectangleBorder(
                  borderRadius: radius.controlBorderRadius,
                ),
                checkboxShape: RoundedRectangleBorder(
                  borderRadius: radius.chipBorderRadius,
                ),
              ),
          ],
        ),
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
    final colors = context.vamoColors;
    final subtitle = _subtitle;
    final tile = Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(item.kind.icon, color: colors.secondary),
        title: Text(item.title),
        subtitle: subtitle == null ? null : Text(subtitle),
        onTap: readOnly ? null : onEdit,
      ),
    );

    if (readOnly) return tile;

    return VamoSlidableRow(
      editLabel: labels.editItem,
      deleteLabel: labels.deleteItem,
      deleteConfirmTitle: labels.deleteConfirmTitle,
      deleteConfirmAction: labels.deleteItem,
      cancelLabel: labels.cancelLabel,
      onEdit: onEdit,
      onDelete: onDelete,
      child: tile,
    );
  }

  String? get _subtitle {
    if (item.kind == PlanItemKind.visit) {
      final visit = parseVisitPlaceMetadata(item.metadata);
      final notes = item.notes?.trim();
      return visit?.address ?? (notes == null || notes.isEmpty ? null : notes);
    }
    return item.notes == null || item.notes!.isEmpty ? null : item.notes;
  }
}
