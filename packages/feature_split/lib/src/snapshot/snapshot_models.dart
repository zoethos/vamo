import '../capture/capture_models.dart';

/// Data composed for the branded share card (Slice 7 + 8 capture highlights).
class SnapshotCardData {
  const SnapshotCardData({
    required this.tripId,
    required this.tripName,
    this.destination,
    this.dateRange,
    required this.totalSpentCents,
    required this.baseCurrency,
    required this.expenseCount,
    required this.members,
    this.capture = const CaptureSnapshotHighlight(),
  });

  final String tripId;
  final String tripName;
  final String? destination;
  final String? dateRange;
  final int totalSpentCents;
  final String baseCurrency;
  final int expenseCount;
  final List<SnapshotMemberAvatar> members;
  final CaptureSnapshotHighlight capture;
}

class SnapshotMemberAvatar {
  const SnapshotMemberAvatar({
    required this.displayName,
  });

  final String displayName;

  String get initial {
    final t = displayName.trim();
    if (t.isEmpty) return '?';
    return t[0].toUpperCase();
  }
}

int totalSpentBaseCents(Iterable<int> baseCentsList) =>
    baseCentsList.fold<int>(0, (sum, c) => sum + c);
