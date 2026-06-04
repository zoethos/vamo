import 'package:app_core/app_core.dart';
import 'package:feature_split/src/snapshot/snapshot_card.dart';
import 'package:feature_split/src/snapshot/snapshot_models.dart';
import 'package:feature_split/src/snapshot/snapshot_themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('SnapshotBrandedCard matches golden', (tester) async {
    final data = SnapshotCardData(
      tripId: 'trip-golden',
      tripName: 'Amalfi Coast Trip',
      destination: 'Positano, Italy',
      dateRange: 'Jun 1 – Jun 14, 2026',
      totalSpentCents: 125000,
      baseCurrency: 'EUR',
      expenseCount: 12,
      members: List.generate(
        4,
        (i) => SnapshotMemberAvatar(displayName: 'Vamigo ${i + 1}'),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          backgroundColor: AppColors.sandLight,
          body: Center(
            child: SnapshotBrandedCard(
              data: data,
              theme: SnapshotThemes.defaultPack,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(SnapshotBrandedCard),
      matchesGoldenFile('goldens/snapshot_branded_card.png'),
    );
  });

  testWidgets('SnapshotBrandedCard Rome theme matches golden', (tester) async {
    final data = SnapshotCardData(
      tripId: 'trip-rome',
      tripName: 'Roman Holiday',
      destination: 'Rome, Italy',
      dateRange: 'Apr 10 – Apr 17, 2026',
      totalSpentCents: 89500,
      baseCurrency: 'EUR',
      expenseCount: 8,
      members: const [
        SnapshotMemberAvatar(displayName: 'Luca'),
        SnapshotMemberAvatar(displayName: 'Giulia'),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          backgroundColor: AppColors.sandLight,
          body: Center(
            child: SnapshotBrandedCard(
              data: data,
              theme: SnapshotThemes.rome,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(SnapshotBrandedCard),
      matchesGoldenFile('goldens/snapshot_rome_theme.png'),
    );
  });
}
