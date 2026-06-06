import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'plan_event_rsvp_chips.dart';
import 'plan_labels.dart';
import 'plan_models.dart';
import 'plan_providers.dart';

class PlanItemSheet extends ConsumerStatefulWidget {
  const PlanItemSheet({
    super.key,
    required this.tripId,
    required this.labels,
    required this.existing,
    required this.readOnly,
    required this.onSave,
  });

  final String tripId;
  final PlanTabLabels labels;
  final PlanItemSummary? existing;
  final bool readOnly;
  final Future<void> Function(PlanItemInput input) onSave;

  @override
  ConsumerState<PlanItemSheet> createState() => _PlanItemSheetState();
}

class _PlanItemSheetState extends ConsumerState<PlanItemSheet> {
  late PlanItemKind _kind;
  late TextEditingController _title;
  late TextEditingController _notes;
  DateTime? _startsAt;
  DateTime? _endsAt;

  @override
  void initState() {
    super.initState();
    _kind = widget.existing?.kind ?? PlanItemKind.other;
    _title = TextEditingController(text: widget.existing?.title ?? '');
    _notes = TextEditingController(text: widget.existing?.notes ?? '');
    _startsAt = widget.existing?.startsAt;
    _endsAt = widget.existing?.endsAt;
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  bool get _isActivity => _kind == PlanItemKind.activity;

  @override
  Widget build(BuildContext context) {
    final eventViews = _isActivity && widget.existing != null
        ? ref.watch(tripPlanEventViewsProvider(widget.tripId))
        : null;
    final eventView =
        widget.existing == null ? null : eventViews?[widget.existing!.id];

    return SafeArea(
      child: Padding(
        padding: EdgeInsetsDirectional.only(
          start: 16,
          end: 16,
          top: 16,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.existing == null
                    ? widget.labels.sheetTitleAdd
                    : widget.labels.sheetTitleEdit,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              InputDecorator(
                decoration: InputDecoration(labelText: widget.labels.fieldKind),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<PlanItemKind>(
                    value: _kind,
                    isExpanded: true,
                    items: PlanItemKind.values
                        .map(
                          (k) => DropdownMenuItem(
                            value: k,
                            child: Row(
                              children: [
                                Icon(k.icon, size: 20),
                                const SizedBox(width: 8),
                                Text(widget.labels.kindLabel(k)),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: widget.readOnly
                        ? null
                        : (v) => setState(() => _kind = v ?? _kind),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _PlanKindBadge(kind: _kind, labels: widget.labels),
              const SizedBox(height: 8),
              TextField(
                controller: _title,
                readOnly: widget.readOnly,
                decoration:
                    InputDecoration(labelText: widget.labels.fieldTitle),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _notes,
                readOnly: widget.readOnly,
                maxLines: 3,
                decoration:
                    InputDecoration(labelText: widget.labels.fieldNotes),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(widget.labels.fieldStart),
                subtitle: Text(_startsAt?.toLocal().toString() ?? '—'),
                trailing: const Icon(Icons.calendar_today_outlined),
                onTap: widget.readOnly ? null : () => _pickDate(isStart: true),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(widget.labels.fieldEnd),
                subtitle: Text(_endsAt?.toLocal().toString() ?? '—'),
                trailing: const Icon(Icons.calendar_today_outlined),
                onTap: widget.readOnly ? null : () => _pickDate(isStart: false),
              ),
              if (_isActivity &&
                  widget.existing != null &&
                  eventView != null) ...[
                const SizedBox(height: 12),
                Text(
                  widget.labels.eventRsvpSection,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 8),
                if (!eventView.counts.isEmpty)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(bottom: 8),
                    child: Text(
                      widget.labels.rsvpSummary(
                        eventView.counts.going,
                        eventView.counts.maybe,
                        eventView.counts.declined,
                      ),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.graphite,
                          ),
                    ),
                  ),
                PlanEventRsvpChips(
                  planItemId: widget.existing!.id,
                  labels: widget.labels,
                  myStatus: eventView.myStatus,
                  readOnly: widget.readOnly,
                ),
              ] else if (_isActivity && widget.existing == null) ...[
                const SizedBox(height: 12),
                Text(
                  widget.labels.eventRsvpHint,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.graphite,
                      ),
                ),
              ],
              const SizedBox(height: 12),
              if (!widget.readOnly)
                FilledButton(
                  onPressed: () async {
                    final title = _title.text.trim();
                    if (title.isEmpty) return;
                    await widget.onSave(
                      PlanItemInput(
                        tripId: widget.tripId,
                        kind: _kind,
                        title: title,
                        notes: _notes.text.trim(),
                        startsAt: _startsAt,
                        endsAt: _endsAt,
                      ),
                    );
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: Text(widget.labels.save),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = (isStart ? _startsAt : _endsAt) ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    if (!context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    final combined = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    ).toUtc();
    setState(() {
      if (isStart) {
        _startsAt = combined;
      } else {
        _endsAt = combined;
      }
    });
  }
}

class _PlanKindBadge extends StatelessWidget {
  const _PlanKindBadge({required this.kind, required this.labels});

  final PlanItemKind kind;
  final PlanTabLabels labels;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Chip(
        avatar: Icon(
          kind.icon,
          size: 18,
          color: AppColors.jadeTeal,
        ),
        label: Text(labels.kindLabel(kind)),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
