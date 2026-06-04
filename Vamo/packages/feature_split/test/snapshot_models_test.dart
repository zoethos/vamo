import 'package:feature_split/src/snapshot/snapshot_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('totalSpentBaseCents sums base cents', () {
    expect(totalSpentBaseCents([3000, 1500, 500]), 5000);
    expect(totalSpentBaseCents([]), 0);
  });

  test('SnapshotMemberAvatar initial', () {
    expect(
      const SnapshotMemberAvatar(displayName: 'Alex').initial,
      'A',
    );
    expect(const SnapshotMemberAvatar(displayName: '').initial, '?');
  });
}
