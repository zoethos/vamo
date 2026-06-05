import 'package:flutter/material.dart';

import 'plan_labels.dart';
import 'plan_models.dart';

class PlanItemSheet extends StatefulWidget {
  const PlanItemSheet({
    super.key,
    required this.tripId,
    required this.labels,
    required this.existing,
    required this.onSave,
  });

  final String tripId;
  final PlanTabLabels labels;
  final PlanItemSummary? existing;
  final Future<void> Function(PlanItemInput input) onSave;

  @override
  State<PlanItemSheet> createState() => _PlanItemSheetState();
}

class _PlanItemSheetState extends State<PlanItemSheet> {
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

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(16, 16, 16, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
            decoration: InputDecoration(labelText: widget.labels.fieldTitle),
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
                onChanged: (v) => setState(() => _kind = v ?? _kind),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _title,
            decoration: InputDecoration(labelText: widget.labels.fieldTitle),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _notes,
            maxLines: 3,
            decoration: InputDecoration(labelText: widget.labels.fieldNotes),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(widget.labels.fieldStart),
            subtitle: Text(_startsAt?.toLocal().toString() ?? '—'),
            trailing: const Icon(Icons.calendar_today_outlined),
            onTap: () => _pickDate(isStart: true),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(widget.labels.fieldEnd),
            subtitle: Text(_endsAt?.toLocal().toString() ?? '—'),
            trailing: const Icon(Icons.calendar_today_outlined),
            onTap: () => _pickDate(isStart: false),
          ),
          const SizedBox(height: 12),
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
