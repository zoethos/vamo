import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Quiet right-aligned `Balances ›` link on the per-trip Expenses screen.
///
/// Connective tissue between the two money surfaces: pushes the Balances
/// section. Hidden (not disabled) when [visible] is false — solo trips have no
/// balances, so the link must not appear. Styled quiet (jade, not lime — lime
/// is reserved for the primary action / future FAB).
class TripExpensesBalancesLink extends StatelessWidget {
  const TripExpensesBalancesLink({
    super.key,
    required this.tripId,
    required this.label,
    required this.visible,
  });

  final String tripId;
  final String label;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    return Semantics(
      button: true,
      label: label,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 0),
        child: Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton(
            onPressed: () => context.push(AppRoutes.tripBalances(tripId)),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.jadeTeal,
              minimumSize: const Size(48, 48),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label),
                const Icon(Icons.chevron_right, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
