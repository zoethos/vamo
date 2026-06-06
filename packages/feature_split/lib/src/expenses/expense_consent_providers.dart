import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'expense_governance.dart';
import 'expenses_providers.dart';
import 'expenses_repository.dart';

final tripExpenseSharesProvider =
    StreamProvider.family<List<ExpenseShareSummary>, String>((ref, tripId) {
  return ref.watch(expensesRepositoryProvider).watchTripExpenseShares(tripId);
});

/// Consent flags for committed expenses where a share is not accepted.
final tripShareConsentFlagsProvider = Provider.family<
    List<({String userId, ShareResponse response, String expenseId})>,
    String>((ref, tripId) {
  final expenses = ref.watch(tripExpensesProvider(tripId)).valueOrNull ?? [];
  final shares = ref.watch(tripExpenseSharesProvider(tripId)).valueOrNull ?? [];

  final committedIds =
      expenses.where((e) => e.status.affectsBalances).map((e) => e.id).toSet();

  return [
    for (final share in shares)
      if (committedIds.contains(share.expenseId) &&
          !share.response.isConsentResolved)
        (
          userId: share.userId,
          expenseId: share.expenseId,
          response: share.response,
        ),
  ];
});

final currentMemberRoleProvider =
    Provider.family<String?, ({String tripId, String? userId})>((ref, args) {
  if (args.userId == null) return null;
  final members =
      ref.watch(tripMembersForExpenseProvider(args.tripId)).valueOrNull ?? [];
  return members
      .where((m) => m.userId == args.userId)
      .map((m) => m.role)
      .firstOrNull;
});

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    if (!it.moveNext()) return null;
    return it.current;
  }
}
