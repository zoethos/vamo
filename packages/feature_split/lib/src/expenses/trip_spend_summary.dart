import 'package:app_core/app_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'expense_consent_providers.dart';
import 'expenses_providers.dart';

/// Per-trip spend rollup backing the Expenses summary header (§B).
class TripSpendSummary {
  const TripSpendSummary({
    required this.totalSpentCents,
    required this.yourShareCents,
  });

  /// Sum of `baseCents` across committed (balance-affecting) expenses.
  final int totalSpentCents;

  /// Current user's summed `shareCents` across those committed expenses.
  final int yourShareCents;

  static const empty = TripSpendSummary(totalSpentCents: 0, yourShareCents: 0);
}

/// Total committed spend + the current user's summed share for [tripId].
///
/// Derives from [tripExpensesProvider] + [tripExpenseSharesProvider] and counts
/// only balance-affecting (committed) expenses — proposals and cancellations
/// are excluded, matching the trip-rollup / balances semantics. This is the
/// spend-led view; the net-balance donut stays on Balances (not duplicated).
final tripSpendSummaryProvider = Provider.family<TripSpendSummary, String>((
  ref,
  tripId,
) {
  final expenses = ref.watch(tripExpensesProvider(tripId)).valueOrNull ?? const [];
  final shares = ref.watch(tripExpenseSharesProvider(tripId)).valueOrNull ?? const [];
  final userId = ref.watch(currentUserProvider)?.id;

  final committedIds = <String>{};
  var total = 0;
  for (final e in expenses) {
    if (e.status.affectsBalances) {
      committedIds.add(e.id);
      total += e.baseCents;
    }
  }

  var yourShare = 0;
  if (userId != null) {
    for (final s in shares) {
      if (s.userId == userId && committedIds.contains(s.expenseId)) {
        yourShare += s.shareCents;
      }
    }
  }

  return TripSpendSummary(totalSpentCents: total, yourShareCents: yourShare);
});
