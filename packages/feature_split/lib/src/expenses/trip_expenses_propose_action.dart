import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

import 'expense_governance_labels.dart';

/// Reserved-lime action FAB on the Expenses screen (§D) — the single lime
/// control on the screen, per the reserved-lime rule.
///
/// Hidden (not disabled) when [visible] is false — read-only trips and members
/// who can't manage proposals. The label is mode-dependent (§0): committed path
/// reads "Add expense"; the proposal/consent path reads "Propose expense".
class TripExpensesProposeAction extends StatelessWidget {
  const TripExpensesProposeAction({
    super.key,
    required this.visible,
    required this.labels,
    required this.onPressed,
    this.mode = AddExpenseMode.proposed,
  });

  final bool visible;
  final ExpenseGovernanceLabels labels;
  final VoidCallback onPressed;
  final AddExpenseMode mode;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    return FloatingActionButton.extended(
      onPressed: onPressed,
      backgroundColor: AppColors.goLime,
      foregroundColor: AppColors.ink,
      icon: const Icon(Icons.add),
      label: Text(labels.actionLabel(mode)),
    );
  }
}
