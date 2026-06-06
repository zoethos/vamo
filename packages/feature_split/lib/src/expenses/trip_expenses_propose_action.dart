import 'package:flutter/material.dart';

import 'expense_governance_labels.dart';
/// Admin-only entry to the propose-expense form. Hidden (not disabled) when
/// [visible] is false — used from trip expenses tab and widget tests.
class TripExpensesProposeAction extends StatelessWidget {
  const TripExpensesProposeAction({
    super.key,
    required this.visible,
    required this.labels,
    required this.onPressed,
  });

  final bool visible;
  final ExpenseGovernanceLabels labels;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 0),
      child: Align(
        alignment: AlignmentDirectional.centerEnd,
        child: TextButton.icon(
          onPressed: onPressed,
          icon: const Icon(Icons.description_outlined),
          label: Text(labels.proposeCostAction),
        ),
      ),
    );
  }
}
