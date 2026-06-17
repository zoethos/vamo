import 'package:app_core/app_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../expenses/expenses_providers.dart';
import 'balances_models.dart';
import 'balances_repository.dart';

final tripNetBalancesProvider =
    StreamProvider.family<({Map<String, int> nets, String currency}), String>(
        (ref, tripId) {
  return ref.watch(balancesRepositoryProvider).watchTripBalances(tripId);
});

final tripSettleUpProvider =
    Provider.family<AsyncValue<List<SettlementDisplay>>, String>((ref, tripId) {
  final balances = ref.watch(tripNetBalancesProvider(tripId));
  final members = ref.watch(tripMembersForExpenseProvider(tripId));

  return balances.when(
    loading: () => const AsyncValue.loading(),
    error: AsyncValue.error,
    data: (data) {
      return members.when(
        loading: () => const AsyncValue.loading(),
        error: AsyncValue.error,
        data: (memberList) {
          final nameById = {for (final m in memberList) m.userId: m.displayName};
          final lines =
              ref.read(balancesRepositoryProvider).settleUpFromNets(data.nets);
          final display = lines
              .map(
                (line) => SettlementDisplay(
                  line: line,
                  fromName: nameById[line.fromUserId] ??
                      fallbackMemberDisplayName(userId: line.fromUserId),
                  toName: nameById[line.toUserId] ??
                      fallbackMemberDisplayName(userId: line.toUserId),
                  currency: data.currency,
                ),
              )
              .toList();
          return AsyncValue.data(display);
        },
      );
    },
  );
});

final tripMemberBalancesProvider =
    Provider.family<AsyncValue<List<MemberBalance>>, String>((ref, tripId) {
  final balances = ref.watch(tripNetBalancesProvider(tripId));
  return balances.when(
    loading: () => const AsyncValue.loading(),
    error: AsyncValue.error,
    data: (data) {
      final list = data.nets.entries
          .map((e) => MemberBalance(userId: e.key, netCents: e.value))
          .where((b) => b.netCents != 0)
          .toList()
        ..sort((a, b) => b.netCents.compareTo(a.netCents));
      return AsyncValue.data(list);
    },
  );
});
