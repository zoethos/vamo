import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/vamo_slidable_row.dart';
import '../trips/trips_providers.dart';
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
  void openAddPlanItem() => _openSheet(context, null, subtripId: null);

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
        await _openSheet(context, null, subtripId: null);
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
    final subtrips = ref.watch(tripSubtripsProvider(widget.tripId));
    final trip = ref.watch(tripDetailProvider(widget.tripId)).valueOrNull;
    final eventViews = ref.watch(tripPlanEventViewsProvider(widget.tripId));
    final repo = ref.read(planRepositoryProvider);
    final subtripsEnabled = trip?.subtripsEnabled == true;

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
            final subtripRows =
                subtrips.valueOrNull ?? const <SubtripSummary>[];
            final grouped = subtripsEnabled
                ? groupPlanItemsBySubtrip(
                    items: planItems,
                    subtrips: subtripRows,
                  )
                : [
                    (
                      subtrip: null,
                      daySections: groupPlanItemsByDay(planItems),
                    ),
                  ];
            final checklists = groupListItemsByName(listItems);

            if (planItems.isEmpty && listItems.isEmpty && !subtripsEnabled) {
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
                      onPressed: () =>
                          _openSheet(context, null, subtripId: null),
                      icon: const Icon(Icons.add),
                      label: Text(widget.labels.addPlanItem),
                    ),
                  ),
                if (subtripsEnabled && !widget.readOnly)
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: OutlinedButton.icon(
                      onPressed: _openCreateSubtripSheet,
                      icon: const Icon(Icons.group_add_outlined),
                      label: Text(widget.labels.addSubtrip),
                    ),
                  ),
                if (subtripsEnabled) SizedBox(height: space.x2),
                for (final group in grouped) ...[
                  _SubtripSectionHeader(
                    title: group.subtrip?.name ?? widget.labels.mainTripSection,
                    memberCount: group.subtrip?.memberIds.length,
                    readOnly: widget.readOnly,
                    addLabel: widget.labels.addPlanItem,
                    onAdd: () => _openSheet(
                      context,
                      null,
                      subtripId: group.subtrip?.id,
                    ),
                  ),
                  SizedBox(height: space.x2),
                  if (group.daySections
                      .every((section) => section.items.isEmpty))
                    Padding(
                      padding: EdgeInsetsDirectional.only(bottom: space.x4),
                      child: Text(
                        widget.labels.emptySubtitle,
                        style: type.bodySmall.copyWith(
                          color: colors.onSurfaceMuted,
                        ),
                      ),
                    ),
                  for (final section in group.daySections) ...[
                    if (section.items.isNotEmpty) ...[
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
                              onEdit: () => _openSheet(
                                context,
                                item,
                                subtripId: item.subtripId,
                              ),
                              onDelete: () => repo.deletePlanItem(item.id),
                            );
                          }
                          return _PlanItemTile(
                            item: item,
                            labels: widget.labels,
                            readOnly: widget.readOnly,
                            onEdit: () => _openSheet(
                              context,
                              item,
                              subtripId: item.subtripId,
                            ),
                            onDelete: () => repo.deletePlanItem(item.id),
                          );
                        },
                      ),
                    ],
                  ],
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

  Future<void> _openSheet(
    BuildContext context,
    PlanItemSummary? existing, {
    required String? subtripId,
  }) {
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
            await ref.read(planRepositoryProvider).addPlanItem(
                  PlanItemInput(
                    tripId: input.tripId,
                    subtripId: subtripId,
                    kind: input.kind,
                    title: input.title,
                    notes: input.notes,
                    startsAt: input.startsAt,
                    endsAt: input.endsAt,
                    metadata: input.metadata,
                  ),
                );
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

  Future<void> _openCreateSubtripSheet() async {
    final nameController = TextEditingController();
    final members =
        ref.read(tripActiveMembersProvider(widget.tripId)).valueOrNull ??
            const <LocalTripMember>[];
    final selected = members.map((m) => m.userId).toSet();
    var saving = false;
    String? error;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final space = ctx.vamoSpace;
          return SafeArea(
            child: Padding(
              padding: EdgeInsetsDirectional.fromSTEB(
                space.x4,
                space.x2,
                space.x4,
                MediaQuery.viewInsetsOf(ctx).bottom + space.x4,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.labels.addSubtrip,
                    style: Theme.of(ctx).textTheme.titleLarge,
                  ),
                  SizedBox(height: space.x3),
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: widget.labels.subtripNameLabel,
                    ),
                    textInputAction: TextInputAction.done,
                  ),
                  SizedBox(height: space.x3),
                  Text(
                    widget.labels.subtripMembersLabel,
                    style: Theme.of(ctx).textTheme.titleSmall,
                  ),
                  SizedBox(height: space.x1),
                  for (final member in members)
                    CheckboxListTile(
                      value: selected.contains(member.userId),
                      onChanged: saving
                          ? null
                          : (value) {
                              setSheetState(() {
                                if (value == true) {
                                  selected.add(member.userId);
                                } else {
                                  selected.remove(member.userId);
                                }
                              });
                            },
                      title: Text(
                        member.displayName?.trim().isNotEmpty == true
                            ? member.displayName!
                            : member.userId,
                      ),
                    ),
                  if (error != null) ...[
                    SizedBox(height: space.x2),
                    Text(
                      error!,
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                            color: Theme.of(ctx).colorScheme.error,
                          ),
                    ),
                  ],
                  SizedBox(height: space.x3),
                  FilledButton(
                    onPressed: saving
                        ? null
                        : () async {
                            final name = nameController.text.trim();
                            if (name.isEmpty) {
                              setSheetState(() {
                                error = widget.labels.subtripNameRequired;
                              });
                              return;
                            }
                            if (selected.isEmpty) {
                              setSheetState(() {
                                error = widget.labels.subtripMembersRequired;
                              });
                              return;
                            }
                            setSheetState(() {
                              saving = true;
                              error = null;
                            });
                            try {
                              await ref
                                  .read(planRepositoryProvider)
                                  .createSubtrip(
                                    tripId: widget.tripId,
                                    name: name,
                                    memberIds: selected.toList(),
                                  );
                              if (ctx.mounted) Navigator.pop(ctx);
                            } catch (e) {
                              setSheetState(() {
                                saving = false;
                                error = widget.labels.subtripCreateFailed;
                              });
                            }
                          },
                    child: saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(widget.labels.addSubtrip),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    nameController.dispose();
  }
}

enum _PlanAddChoice { planItem, checklistItem }

class _SubtripSectionHeader extends StatelessWidget {
  const _SubtripSectionHeader({
    required this.title,
    required this.memberCount,
    required this.readOnly,
    required this.addLabel,
    required this.onAdd,
  });

  final String title;
  final int? memberCount;
  final bool readOnly;
  final String addLabel;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = context.vamoColors;
    final type = context.vamoType;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: type.titleMedium.copyWith(
                  fontWeight: FontWeight.w800,
                  color: colors.onSurface,
                ),
              ),
              if (memberCount != null)
                Text(
                  '$memberCount members',
                  style: type.bodySmall.copyWith(
                    color: colors.onSurfaceMuted,
                  ),
                ),
            ],
          ),
        ),
        if (!readOnly)
          IconButton(
            tooltip: addLabel,
            onPressed: onAdd,
            icon: const Icon(Icons.add_circle_outline),
          ),
      ],
    );
  }
}

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
    if (item.kind == PlanItemKind.transfer) {
      final transfer = parseTransferMetadata(item.metadata);
      final route = _transferRoute(transfer);
      if (route != null) return route;
      final provider = transfer?.provider;
      if (provider != null) return provider;
    }
    return item.notes == null || item.notes!.isEmpty ? null : item.notes;
  }

  String? _transferRoute(TransferMetadata? transfer) {
    final origin = transfer?.origin;
    final destination = transfer?.destination;
    if (origin == null && destination == null) return null;
    if (origin == null) return destination;
    if (destination == null) return origin;
    return '$origin -> $destination';
  }
}
