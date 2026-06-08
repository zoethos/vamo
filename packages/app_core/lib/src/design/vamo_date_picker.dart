import 'package:flutter/material.dart';

/// Labels for the three-action date picker (Cancel · Skip · Select).
class VamoDatePickerLabels {
  const VamoDatePickerLabels({
    required this.cancel,
    required this.skip,
    required this.select,
  });

  final String cancel;
  final String skip;
  final String select;
}

enum VamoDatePickOutcome { cancelled, skipped, selected }

class VamoDatePickResult {
  const VamoDatePickResult._(this.outcome, [this.date]);

  const VamoDatePickResult.cancelled() : this._(VamoDatePickOutcome.cancelled);

  const VamoDatePickResult.skipped() : this._(VamoDatePickOutcome.skipped);

  const VamoDatePickResult.selected(DateTime date)
      : this._(VamoDatePickOutcome.selected, date);

  final VamoDatePickOutcome outcome;
  final DateTime? date;
}

/// Date picker with Cancel (abort), Skip (no date), Select (confirm).
Future<VamoDatePickResult> showVamoDatePicker({
  required BuildContext context,
  required VamoDatePickerLabels labels,
  DateTime? initialDate,
  DateTime? firstDate,
  DateTime? lastDate,
}) async {
  final first = firstDate ?? DateTime(2020);
  final last = lastDate ?? DateTime(2100);
  var selected = initialDate ?? DateTime.now();
  if (selected.isBefore(first)) selected = first;
  if (selected.isAfter(last)) selected = last;

  final outcome = await showDialog<VamoDatePickOutcome>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            contentPadding: const EdgeInsetsDirectional.fromSTEB(0, 12, 0, 0),
            content: SizedBox(
              width: 340,
              height: 360,
              child: CalendarDatePicker(
                initialDate: selected,
                firstDate: first,
                lastDate: last,
                onDateChanged: (value) => setState(() => selected = value),
              ),
            ),
            actionsPadding: const EdgeInsetsDirectional.fromSTEB(8, 0, 8, 8),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.pop(ctx, VamoDatePickOutcome.cancelled),
                child: Text(labels.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, VamoDatePickOutcome.skipped),
                child: Text(labels.skip),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.pop(ctx, VamoDatePickOutcome.selected),
                child: Text(labels.select),
              ),
            ],
          );
        },
      );
    },
  );

  return switch (outcome) {
    VamoDatePickOutcome.skipped => const VamoDatePickResult.skipped(),
    VamoDatePickOutcome.selected => VamoDatePickResult.selected(selected),
    VamoDatePickOutcome.cancelled || null => const VamoDatePickResult.cancelled(),
  };
}
