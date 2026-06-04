/// Deterministic minimal settle-up — pure integer math, no I/O (T6.1).
class SettlementLine {
  const SettlementLine({
    required this.fromUserId,
    required this.toUserId,
    required this.cents,
  });

  final String fromUserId;
  final String toUserId;
  final int cents;
}

class _Party {
  _Party(this.userId, this.cents);
  String userId;
  int cents;
}

/// From per-member [netCents] (trip base currency): positive = creditor,
/// negative = debtor. Returns the minimum number of "X pays Y" lines that
/// clear the trip.
List<SettlementLine> settleUp(Map<String, int> netCents) {
  final creditors = <_Party>[];
  final debtors = <_Party>[];

  for (final entry in netCents.entries) {
    if (entry.value > 0) {
      creditors.add(_Party(entry.key, entry.value));
    } else if (entry.value < 0) {
      debtors.add(_Party(entry.key, -entry.value));
    }
  }

  creditors.sort(_comparePartiesLargestFirst);
  debtors.sort(_comparePartiesLargestFirst);

  final out = <SettlementLine>[];
  var i = 0;
  var j = 0;
  while (i < debtors.length && j < creditors.length) {
    final pay = debtors[i].cents < creditors[j].cents
        ? debtors[i].cents
        : creditors[j].cents;
    if (pay > 0) {
      out.add(
        SettlementLine(
          fromUserId: debtors[i].userId,
          toUserId: creditors[j].userId,
          cents: pay,
        ),
      );
    }
    debtors[i].cents -= pay;
    creditors[j].cents -= pay;
    if (debtors[i].cents == 0) i++;
    if (creditors[j].cents == 0) j++;
  }

  return out;
}

/// Mirrors Postgres `trip_balances` (includes marked + confirmed settlements).
Map<String, int> computeNetBalances({
  required Iterable<String> activeMemberIds,
  required Iterable<({String payerId, int baseCents})> expenses,
  required Iterable<({String userId, int shareCents})> shares,
  Map<String, int> settledOut = const {},
  Map<String, int> settledIn = const {},
}) {
  final paid = <String, int>{};
  final owed = <String, int>{};

  for (final e in expenses) {
    paid[e.payerId] = (paid[e.payerId] ?? 0) + e.baseCents;
  }
  for (final s in shares) {
    owed[s.userId] = (owed[s.userId] ?? 0) + s.shareCents;
  }

  final nets = <String, int>{};
  for (final id in activeMemberIds) {
    nets[id] = (paid[id] ?? 0) -
        (owed[id] ?? 0) +
        (settledOut[id] ?? 0) -
        (settledIn[id] ?? 0);
  }
  return nets;
}

/// Largest cents first; tie-break by [userId] for stable, reproducible output.
int _comparePartiesLargestFirst(_Party a, _Party b) {
  final byCents = b.cents.compareTo(a.cents);
  if (byCents != 0) return byCents;
  return a.userId.compareTo(b.userId);
}
