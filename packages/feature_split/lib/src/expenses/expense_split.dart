/// Pure split math — no I/O. Covered by unit tests (Slice 2 / T5.2).
class ExpenseShareLine {
  const ExpenseShareLine({required this.userId, required this.shareCents});

  final String userId;
  final int shareCents;
}

/// Splits [baseCents] equally across [memberIds]. Remainder cents go to the
/// first members in sorted user-id order (deterministic, matches spec residue rule).
List<ExpenseShareLine> equalSplit({
  required int baseCents,
  required List<String> memberIds,
}) {
  if (baseCents <= 0) {
    throw ArgumentError.value(baseCents, 'baseCents', 'must be positive');
  }
  if (memberIds.isEmpty) {
    throw ArgumentError('memberIds must not be empty');
  }

  final sorted = [...memberIds]..sort();
  final n = sorted.length;
  final base = baseCents ~/ n;
  final remainder = baseCents % n;

  return [
    for (var i = 0; i < sorted.length; i++)
      ExpenseShareLine(
        userId: sorted[i],
        shareCents: base + (i < remainder ? 1 : 0),
      ),
  ];
}

/// Enforces the Wave 1 invariant before any write.
void assertSharesSumToBase({
  required int baseCents,
  required Iterable<int> shareCents,
}) {
  final sum = shareCents.fold<int>(0, (a, b) => a + b);
  if (sum != baseCents) {
    throw StateError('sum(shares)=$sum must equal base_cents=$baseCents');
  }
}

/// Validates an explicit split before it is written locally or sent to the
/// server. Every active member is named exactly once; a zero share is explicit.
List<ExpenseShareLine> validateCustomSplit({
  required int baseCents,
  required List<String> memberIds,
  required List<ExpenseShareLine> shares,
}) {
  if (baseCents <= 0) {
    throw ArgumentError.value(baseCents, 'baseCents', 'must be positive');
  }
  final expected = memberIds.toSet();
  final actual = shares.map((share) => share.userId).toSet();
  if (expected.length != memberIds.length ||
      actual.length != shares.length ||
      actual.length != expected.length ||
      !actual.containsAll(expected)) {
    throw ArgumentError('Custom split must include each active member once.');
  }
  if (shares.any((share) => share.shareCents < 0)) {
    throw ArgumentError('Custom split amounts cannot be negative.');
  }
  assertSharesSumToBase(
    baseCents: baseCents,
    shareCents: shares.map((share) => share.shareCents),
  );
  return shares;
}
