import 'package:app_core/app_core.dart';
import 'package:feature_split/src/expenses/trip_expense_list_tile.dart';
import 'package:feature_split/src/snapshot/snapshot_card.dart';
import 'package:feature_split/src/snapshot/snapshot_models.dart';
import 'package:feature_split/src/snapshot/snapshot_themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_test_theme.dart';

void main() {
  const arLocale = Locale('ar');

  Widget rtlHarness({required Widget child}) {
    return ProviderScope(
      child: MaterialApp(
        theme: goldenTestTheme(),
        locale: arLocale,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocales.supported,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            backgroundColor: AppColors.blush,
            body: Center(child: child),
          ),
        ),
      ),
    );
  }

  testWidgets('SnapshotBrandedCard RTL golden', (tester) async {
    final data = SnapshotCardData(
      tripId: 'trip-rtl',
      tripName: 'رحلة العائلة',
      destination: 'مراكش، المغرب',
      dateRange: '١ – ١٤ يونيو ٢٠٢٦',
      totalSpentCents: 125000,
      baseCurrency: 'EUR',
      expenseCount: 12,
      members: const [
        SnapshotMemberAvatar(displayName: 'أحمد'),
        SnapshotMemberAvatar(displayName: 'سارة'),
      ],
    );

    await tester.pumpWidget(
      rtlHarness(
        child: SnapshotBrandedCard(
          data: data,
          theme: SnapshotThemes.defaultPack,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(SnapshotBrandedCard),
      matchesGoldenFile('goldens/snapshot_branded_card_rtl_ar.png'),
    );
  });

  testWidgets('Trip expense list RTL golden', (tester) async {
    await tester.pumpWidget(
      rtlHarness(
        child: SizedBox(
          width: 400,
          child: TripExpenseListTile(
            description: 'عشاء جماعي',
            payer: 'أحمد',
            spentAt: DateTime(2026, 6, 2),
            baseCents: 4500,
            amountCents: 4500,
            tripBaseCurrency: 'EUR',
            expenseCurrency: 'EUR',
            locale: 'ar',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(TripExpenseListTile),
      matchesGoldenFile('goldens/trip_expense_list_tile_rtl_ar.png'),
    );
  });

  testWidgets('Trip home header RTL golden', (tester) async {
    await tester.pumpWidget(
      rtlHarness(
        child: SizedBox(
          width: 400,
          child: DefaultTabController(
            length: 2,
            child: AppBar(
              title: const Text('رحلة العائلة'),
              bottom: const TabBar(
                tabs: [
                  Tab(text: 'المصروفات'),
                  Tab(text: 'الأعضاء'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(AppBar),
      matchesGoldenFile('goldens/trip_home_appbar_rtl_ar.png'),
    );
  });
}
