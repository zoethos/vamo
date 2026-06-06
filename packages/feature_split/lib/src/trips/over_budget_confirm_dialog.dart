import 'package:flutter/material.dart';

import 'trip_budget_labels.dart';

/// Typed confirmation for formal over-budget commits (A3 — client-only gate).
Future<bool> confirmFormalOverBudgetCommit({
  required BuildContext context,
  required TripBudgetLabels labels,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => _OverBudgetConfirmDialog(labels: labels),
  );
  return result ?? false;
}

class _OverBudgetConfirmDialog extends StatefulWidget {
  const _OverBudgetConfirmDialog({required this.labels});

  final TripBudgetLabels labels;

  @override
  State<_OverBudgetConfirmDialog> createState() =>
      _OverBudgetConfirmDialogState();
}

class _OverBudgetConfirmDialogState extends State<_OverBudgetConfirmDialog> {
  late final TextEditingController _controller;
  late final String _phrase;

  @override
  void initState() {
    super.initState();
    _phrase = widget.labels.overBudgetConfirmPhrase;
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final labels = widget.labels;
    return AlertDialog(
      title: Text(labels.overBudgetCommitTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(labels.overBudgetCommitBody),
            const SizedBox(height: 16),
            Text(labels.overBudgetConfirmHint(_phrase)),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(labelText: _phrase),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(labels.cancel),
        ),
        FilledButton(
          onPressed: _controller.text.trim() == _phrase
              ? () => Navigator.pop(context, true)
              : null,
          child: Text(labels.confirm),
        ),
      ],
    );
  }
}
