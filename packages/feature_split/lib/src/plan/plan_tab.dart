import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../places/place_resolve.dart';
import '../shared/vamo_slidable_row.dart';
import 'event_rsvp_models.dart';
import 'plan_event_rsvp_picker.dart';
import 'plan_item_sheet.dart';
import 'plan_labels.dart';
import 'plan_models.dart';
import 'plan_providers.dart';
import 'plan_repository.dart';
import 'plan_type_visuals.dart';

class PlanTab extends ConsumerStatefulWidget {
  const PlanTab({
    super.key,
    required this.tripId,
    required this.labels,
    required this.readOnly,
    this.tripStartDateIso,
    this.tripEndDateIso,
    this.tripDestination,
    this.showInlineAddAction = false,
    this.showBottomAddAction = false,
  });

  final String tripId;
  final PlanTabLabels labels;
  final bool readOnly;
  final String? tripStartDateIso;
  final String? tripEndDateIso;
  final String? tripDestination;

  /// Legacy inline add controls — S38 uses header "+" + add menu instead.
  final bool showInlineAddAction;
  final bool showBottomAddAction;

  @override
  ConsumerState<PlanTab> createState() => PlanTabState();
}

class PlanTabState extends ConsumerState<PlanTab> {
  DateTime? _selectedDay;

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
            final checklists = groupListItemsByName(listItems);

            return _PlanTabContent(
              planItems: planItems,
              checklists: checklists,
              eventViews: eventViews,
              labels: widget.labels,
              readOnly: widget.readOnly,
              showInlineAddAction: widget.showInlineAddAction,
              showBottomAddAction: widget.showBottomAddAction,
              tripStartDateIso: widget.tripStartDateIso,
              tripEndDateIso: widget.tripEndDateIso,
              tripDestination: widget.tripDestination,
              selectedDay: _selectedDay,
              onSelectedDayChanged: (day) => setState(() {
                _selectedDay = day;
              }),
              onAddPlanItem: () => _openSheet(context, null),
              onEditPlanItem: (item) => _openSheet(context, item),
              onDeletePlanItem: (item) => repo.deletePlanItem(item.id),
              onToggleChecklistItem: (id) => repo.toggleListItem(id),
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

class _PlanTabContent extends StatelessWidget {
  const _PlanTabContent({
    required this.planItems,
    required this.checklists,
    required this.eventViews,
    required this.labels,
    required this.readOnly,
    required this.showInlineAddAction,
    required this.showBottomAddAction,
    required this.tripStartDateIso,
    required this.tripEndDateIso,
    required this.tripDestination,
    required this.selectedDay,
    required this.onSelectedDayChanged,
    required this.onAddPlanItem,
    required this.onEditPlanItem,
    required this.onDeletePlanItem,
    required this.onToggleChecklistItem,
  });

  final List<PlanItemSummary> planItems;
  final Map<String, List<TripListItemSummary>> checklists;
  final Map<String, PlanItemEventView> eventViews;
  final PlanTabLabels labels;
  final bool readOnly;
  final bool showInlineAddAction;
  final bool showBottomAddAction;
  final String? tripStartDateIso;
  final String? tripEndDateIso;
  final String? tripDestination;
  final DateTime? selectedDay;
  final ValueChanged<DateTime> onSelectedDayChanged;
  final VoidCallback onAddPlanItem;
  final ValueChanged<PlanItemSummary> onEditPlanItem;
  final ValueChanged<PlanItemSummary> onDeletePlanItem;
  final ValueChanged<String> onToggleChecklistItem;

  @override
  Widget build(BuildContext context) {
    final colors = context.vamoColors;
    final type = context.vamoType;
    final space = context.vamoSpace;
    final grouped = groupPlanItemsByDay(planItems);
    final days = _timelineDays(planItems, tripStartDateIso, tripEndDateIso);
    final effectiveSelectedDay =
        _selectedDayFor(days: days, selectedDay: selectedDay);
    final selectedKey =
        effectiveSelectedDay == null ? null : _dayKey(effectiveSelectedDay);
    final visibleSections = selectedKey == null
        ? grouped
        : grouped.where((section) => section.dayKey == selectedKey).toList();
    final hasBody = planItems.isNotEmpty || checklists.isNotEmpty;
    final bottomInset = (!readOnly && showBottomAddAction) ? 104.0 : 16.0;

    return Stack(
      children: [
        if (!hasBody)
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              space.x4,
              space.x4,
              space.x4,
              bottomInset,
            ),
            child: Center(
              child: AppEmptyState(
                screen: 'trip_plan',
                icon: Icons.route_outlined,
                title: labels.emptyTitle,
                subtitle: labels.emptySubtitle,
              ),
            ),
          )
        else
          ListView(
            padding: EdgeInsetsDirectional.fromSTEB(
              space.x4,
              space.x4,
              space.x4,
              bottomInset,
            ),
            children: [
              if (!readOnly && showInlineAddAction)
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton.icon(
                    onPressed: onAddPlanItem,
                    icon: const Icon(Icons.add),
                    label: Text(labels.addPlanItem),
                  ),
                ),
              if (days.isNotEmpty) ...[
                SizedBox(
                  height: 70,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: days.length,
                    separatorBuilder: (_, __) => SizedBox(width: space.x2),
                    itemBuilder: (context, index) {
                      final day = days[index];
                      return _DayPill(
                        date: day,
                        selected: _isSameDay(day, effectiveSelectedDay),
                        onTap: () => onSelectedDayChanged(day),
                      );
                    },
                  ),
                ),
                SizedBox(height: space.x3),
              ],
              if (visibleSections.isEmpty && selectedKey != null)
                Padding(
                  padding: EdgeInsetsDirectional.only(bottom: space.x6),
                  child: Text(
                    labels.emptySubtitle,
                    style: type.bodyMedium.copyWith(
                      color: colors.onSurfaceMuted,
                    ),
                  ),
                ),
              for (final section in visibleSections) ...[
                _TimelineSectionHeader(
                  dayKey: section.dayKey,
                  labels: labels,
                  tripDestination: tripDestination,
                ),
                SizedBox(height: space.x2),
                for (final (index, item) in section.items.indexed)
                  _PlanTimelineRow(
                    item: item,
                    nextItem: index == section.items.length - 1
                        ? null
                        : section.items[index + 1],
                    eventView: eventViews[item.id],
                    labels: labels,
                    readOnly: readOnly,
                    onEdit: () => onEditPlanItem(item),
                    onDelete: () => onDeletePlanItem(item),
                  ),
                SizedBox(height: space.x4),
              ],
              if (checklists.isNotEmpty) ...[
                Text(
                  labels.checklistsSection,
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
                    readOnly: readOnly,
                    onToggle: onToggleChecklistItem,
                  ),
              ],
            ],
          ),
        if (!readOnly && showBottomAddAction)
          PositionedDirectional(
            start: space.x4,
            end: space.x4,
            bottom: space.x4,
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: 56,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.action,
                    foregroundColor: colors.onAction,
                    textStyle: type.titleSmall.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  onPressed: onAddPlanItem,
                  icon: const Icon(Icons.add),
                  label: Text(labels.addPlanItem),
                ),
              ),
            ),
          ),
      ],
    );
  }

  static DateTime? _selectedDayFor({
    required List<DateTime> days,
    required DateTime? selectedDay,
  }) {
    if (days.isEmpty) return null;
    if (selectedDay == null) return days.first;
    return days.firstWhere(
      (day) => _isSameDay(day, selectedDay),
      orElse: () => days.first,
    );
  }

  static List<DateTime> _timelineDays(
    List<PlanItemSummary> items,
    String? startIso,
    String? endIso,
  ) {
    final start = _parseIsoDay(startIso);
    final end = _parseIsoDay(endIso) ?? start;
    final days = <DateTime>{};
    if (start != null && end != null && !end.isBefore(start)) {
      final count = end.difference(start).inDays + 1;
      if (count <= 45) {
        for (var i = 0; i < count; i++) {
          days.add(DateTime(start.year, start.month, start.day + i));
        }
      }
    }
    for (final item in items) {
      final startAt = item.startsAt?.toLocal();
      if (startAt != null) {
        days.add(DateTime(startAt.year, startAt.month, startAt.day));
      }
    }
    return days.toList()..sort();
  }

  static DateTime? _parseIsoDay(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final parsed = DateTime.tryParse(raw.trim());
    if (parsed == null) return null;
    final local = parsed.toLocal();
    return DateTime(local.year, local.month, local.day);
  }
}

class _DayPill extends StatelessWidget {
  const _DayPill({
    required this.date,
    required this.selected,
    required this.onTap,
  });

  final DateTime date;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.vamoColors;
    final type = context.vamoType;
    final background = selected ? colors.onBackground : colors.surfaceMuted;
    final foreground = selected ? colors.background : colors.onSurfaceMuted;

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            width: 58,
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(vertical: 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    DateFormat.E().format(date).toUpperCase(),
                    style: type.labelSmall.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    DateFormat.d().format(date),
                    style: type.titleMedium.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TimelineSectionHeader extends StatelessWidget {
  const _TimelineSectionHeader({
    required this.dayKey,
    required this.labels,
    required this.tripDestination,
  });

  final String? dayKey;
  final PlanTabLabels labels;
  final String? tripDestination;

  @override
  Widget build(BuildContext context) {
    final colors = context.vamoColors;
    final type = context.vamoType;
    final day = _parseDayKey(dayKey);
    final destination = tripDestination?.trim();
    final dateLabel = day == null
        ? labels.undatedSection
        : DateFormat('EEE, MMM d').format(day);
    final label = destination == null || destination.isEmpty
        ? dateLabel
        : '$dateLabel - $destination';

    return Text(
      label,
      style: type.titleSmall.copyWith(
        fontWeight: FontWeight.w800,
        color: colors.onSurfaceMuted,
      ),
    );
  }

  static DateTime? _parseDayKey(String? raw) {
    if (raw == null) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
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

class _PlanTimelineRow extends StatelessWidget {
  const _PlanTimelineRow({
    required this.item,
    required this.nextItem,
    required this.eventView,
    required this.labels,
    required this.readOnly,
    required this.onEdit,
    required this.onDelete,
  });

  final PlanItemSummary item;
  final PlanItemSummary? nextItem;
  final PlanItemEventView? eventView;
  final PlanTabLabels labels;
  final bool readOnly;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final space = context.vamoSpace;
    final leg = _distanceToNextStop;
    final row = Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TimelineTimeColumn(item: item),
              SizedBox(width: space.x2),
              _TimelineSpine(kind: item.kind),
              SizedBox(width: space.x3),
              Expanded(
                child: _PlanTimelineCard(
                  item: item,
                  eventView: eventView,
                  labels: labels,
                  readOnly: readOnly,
                  onTap: readOnly ? null : onEdit,
                ),
              ),
            ],
          ),
        ),
        if (leg != null)
          Padding(
            padding: EdgeInsetsDirectional.only(
              start: 90,
              top: space.x1,
              bottom: space.x2,
            ),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: _DistancePill(label: leg),
            ),
          )
        else
          SizedBox(height: space.x2),
      ],
    );

    if (readOnly) return row;

    return VamoSlidableRow(
      editLabel: labels.editItem,
      deleteLabel: labels.deleteItem,
      deleteConfirmTitle: labels.deleteConfirmTitle,
      deleteConfirmAction: labels.deleteItem,
      cancelLabel: labels.cancelLabel,
      onEdit: onEdit,
      onDelete: onDelete,
      child: row,
    );
  }

  String? get _distanceToNextStop {
    final current = _visitCoords(item);
    if (current == null) return null;
    final next = nextItem == null ? null : _visitCoords(nextItem!);
    if (next == null) return null;
    final travelKinds = {
      PlanItemKind.transfer,
      PlanItemKind.flight,
      PlanItemKind.train,
    };
    if (travelKinds.contains(item.kind) ||
        travelKinds.contains(nextItem!.kind)) {
      return null;
    }
    final meters = distanceMeters(
      current.$1,
      current.$2,
      next.$1,
      next.$2,
    );
    return '${_formatDistance(meters)} - ${_formatWalkTime(meters)} walk';
  }

  (double, double)? _visitCoords(PlanItemSummary row) {
    if (row.kind != PlanItemKind.visit && row.kind != PlanItemKind.lodging) {
      return null;
    }
    final metadata = parsePlanMetadata(row.metadata);
    final lat = _metadataDouble(metadata['lat']);
    final lng = _metadataDouble(metadata['lng']);
    if (lat == null || lng == null) return null;
    return (lat, lng);
  }

  String _formatDistance(double meters) {
    if (meters >= 1000) {
      final km = meters / 1000;
      return '${km >= 10 ? km.toStringAsFixed(0) : km.toStringAsFixed(1)} km';
    }
    return '${meters.round()} m';
  }

  String _formatWalkTime(double meters) {
    final minutes = (meters / 80).round().clamp(1, 180);
    if (minutes >= 60) {
      final hours = minutes / 60;
      return '${hours.toStringAsFixed(hours >= 10 ? 0 : 1)} h';
    }
    return '$minutes min';
  }
}

class _TimelineTimeColumn extends StatelessWidget {
  const _TimelineTimeColumn({required this.item});

  final PlanItemSummary item;

  @override
  Widget build(BuildContext context) {
    final colors = context.vamoColors;
    final type = context.vamoType;
    final startsAt = item.startsAt?.toLocal();
    final time = startsAt == null ? null : DateFormat.Hm().format(startsAt);
    final duration = _durationLabel(item);

    return SizedBox(
      width: 54,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(top: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              time ?? '--:--',
              style: type.labelLarge.copyWith(
                color: time == null ? colors.onSurfaceMuted : colors.onSurface,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (duration != null)
              Text(
                duration,
                style: type.labelSmall.copyWith(
                  color: colors.onSurfaceMuted.withValues(alpha: 0.58),
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String? _durationLabel(PlanItemSummary item) {
    final start = item.startsAt;
    final end = item.endsAt;
    if (start == null || end == null || !end.isAfter(start)) return null;
    final minutes = end.difference(start).inMinutes;
    if (minutes <= 0) return null;
    if (minutes < 60) return '${minutes}m';
    if (minutes % 60 == 0) return '${minutes ~/ 60}h';
    final hours = minutes / 60;
    return '${hours.toStringAsFixed(1)}h';
  }
}

class _TimelineSpine extends StatelessWidget {
  const _TimelineSpine({required this.kind});

  final PlanItemKind kind;

  @override
  Widget build(BuildContext context) {
    final visual = visualForPlanKind(kind);
    final colors = context.vamoColors;

    return SizedBox(
      width: 20,
      child: Column(
        children: [
          const SizedBox(height: 16),
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: visual.accent, width: 2),
              color: colors.background,
            ),
          ),
          Expanded(
            child: Container(
              width: 2,
              margin: const EdgeInsetsDirectional.only(top: 4),
              color: colors.divider.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanTimelineCard extends StatelessWidget {
  const _PlanTimelineCard({
    required this.item,
    required this.eventView,
    required this.labels,
    required this.readOnly,
    required this.onTap,
  });

  final PlanItemSummary item;
  final PlanItemEventView? eventView;
  final PlanTabLabels labels;
  final bool readOnly;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.vamoColors;
    final type = context.vamoType;
    final space = context.vamoSpace;
    final visual = visualForPlanKind(item.kind);
    final subtitle = _subtitle;

    return Material(
      color: colors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colors.divider.withValues(alpha: 0.8)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(space.x3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _PlanItemMedia(item: item),
                  SizedBox(width: space.x3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: type.titleSmall.copyWith(
                            color: colors.onSurface,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: type.bodySmall.copyWith(
                              color: colors.onSurfaceMuted.withValues(
                                alpha: 0.72,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              if (eventView != null &&
                  (!eventView!.counts.isEmpty || !readOnly))
                Padding(
                  padding: EdgeInsetsDirectional.only(top: space.x3),
                  child: Row(
                    children: [
                      if (!eventView!.counts.isEmpty) ...[
                        _RsvpCountSummary(
                          counts: eventView!.counts,
                          accent: visual.accent,
                          labels: labels,
                        ),
                        const Spacer(),
                      ],
                      if (!readOnly)
                        PlanEventRsvpControl(
                          planItemId: item.id,
                          labels: labels,
                          myStatus: eventView!.myStatus,
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String? get _subtitle {
    if (item.kind == PlanItemKind.visit || item.kind == PlanItemKind.lodging) {
      final visit = parseVisitPlaceMetadata(item.metadata);
      final address = visit?.address?.trim();
      if (address != null && address.isNotEmpty) return address;
    }
    if (item.kind == PlanItemKind.transfer) {
      final transfer = parseTransferMetadata(item.metadata);
      final route = _transferRoute(transfer);
      if (route != null) return route;
      final provider = transfer?.provider;
      if (provider != null) return provider;
    }
    final notes = item.notes?.trim();
    return notes == null || notes.isEmpty ? null : notes;
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

class _PlanItemMedia extends StatelessWidget {
  const _PlanItemMedia({required this.item});

  final PlanItemSummary item;

  @override
  Widget build(BuildContext context) {
    final visual = visualForPlanKind(item.kind);
    final place = parseVisitPlaceMetadata(item.metadata);
    final isPlaceType =
        item.kind == PlanItemKind.visit || item.kind == PlanItemKind.lodging;
    final photoUrl = isPlaceType ? place?.photoUrl : null;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 58,
            height: 58,
            child: photoUrl == null
                ? _PlanMediaFallback(kind: item.kind)
                : Image.network(
                    photoUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        _PlanMediaFallback(kind: item.kind),
                  ),
          ),
        ),
        PositionedDirectional(
          end: -5,
          bottom: -5,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: visual.accent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: context.vamoColors.surface, width: 2),
            ),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(visual.icon, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

class _PlanMediaFallback extends StatelessWidget {
  const _PlanMediaFallback({required this.kind});

  final PlanItemKind kind;

  @override
  Widget build(BuildContext context) {
    final visual = visualForPlanKind(kind);
    final isPlaceType =
        kind == PlanItemKind.visit || kind == PlanItemKind.lodging;
    if (isPlaceType) {
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: AlignmentDirectional.topStart,
            end: AlignmentDirectional.bottomEnd,
            colors: [
              visual.accent.withValues(alpha: 0.86),
              visual.accent.withValues(alpha: 0.52),
            ],
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(color: visual.accent.withValues(alpha: 0.1)),
      child: Icon(visual.icon, color: visual.accent, size: 28),
    );
  }
}

class _RsvpCountSummary extends StatelessWidget {
  const _RsvpCountSummary({
    required this.counts,
    required this.accent,
    required this.labels,
  });

  final EventRsvpCounts counts;
  final Color accent;
  final PlanTabLabels labels;

  @override
  Widget build(BuildContext context) {
    final colors = context.vamoColors;
    final type = context.vamoType;

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        if (counts.going > 0)
          _RsvpCountChip(
            label: '${counts.going} ${labels.rsvpGoing}',
            foreground: Colors.white,
            background: accent,
            textStyle: type.labelSmall,
          ),
        if (counts.maybe > 0)
          _RsvpCountChip(
            label: '${counts.maybe} ${labels.rsvpMaybe}',
            foreground: colors.onSurface,
            background: colors.warning.withValues(alpha: 0.35),
            textStyle: type.labelSmall,
          ),
        if (counts.declined > 0)
          _RsvpCountChip(
            label: '${counts.declined} ${labels.rsvpDeclined}',
            foreground: colors.error,
            background: colors.error.withValues(alpha: 0.12),
            textStyle: type.labelSmall,
          ),
      ],
    );
  }
}

class _RsvpCountChip extends StatelessWidget {
  const _RsvpCountChip({
    required this.label,
    required this.foreground,
    required this.background,
    required this.textStyle,
  });

  final String label;
  final Color foreground;
  final Color background;
  final TextStyle textStyle;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: 10,
          vertical: 5,
        ),
        child: Text(
          label,
          maxLines: 1,
          softWrap: false,
          style: textStyle.copyWith(
            color: foreground,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _DistancePill extends StatelessWidget {
  const _DistancePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.vamoColors;
    final type = context.vamoType;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.divider.withValues(alpha: 0.72)),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: 10,
          vertical: 5,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.directions_walk_outlined,
              size: 14,
              color: colors.onSurfaceMuted.withValues(alpha: 0.48),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: type.labelSmall.copyWith(
                color: colors.onSurfaceMuted.withValues(alpha: 0.58),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

bool _isSameDay(DateTime? a, DateTime? b) {
  if (a == null || b == null) return false;
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

String _dayKey(DateTime day) {
  final month = day.month.toString().padLeft(2, '0');
  final dayOfMonth = day.day.toString().padLeft(2, '0');
  return '${day.year}-$month-$dayOfMonth';
}

double? _metadataDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}
