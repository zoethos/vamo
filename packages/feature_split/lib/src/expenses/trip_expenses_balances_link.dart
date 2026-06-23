import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Quiet `Balances ›` link that lives in the Expenses summary header (§B).
///
/// Connective tissue between the two money surfaces: pushes the Balances
/// section. Hidden (not disabled) when [visible] is false — solo trips have no
/// balances, so the link must not appear. Styled quiet (not lime — lime is
/// reserved for the action FAB). [foregroundColor] lets the caller tune
/// contrast against light vs. dark surfaces; defaults to jade.
class TripExpensesBalancesLink extends StatelessWidget {
  const TripExpensesBalancesLink({
    super.key,
    required this.tripId,
    required this.label,
    required this.visible,
    this.foregroundColor = AppColors.jadeTeal,
  });

  final String tripId;
  final String label;
  final bool visible;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    return Semantics(
      button: true,
      label: label,
      child: TextButton(
        onPressed: () => context.push(AppRoutes.tripBalances(tripId)),
        style: TextButton.styleFrom(
          foregroundColor: foregroundColor,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 8, 8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label),
            const Icon(Icons.chevron_right, size: 18),
          ],
        ),
      ),
    );
  }
}
