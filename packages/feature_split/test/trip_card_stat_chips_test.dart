import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:feature_split/src/trips/trip_card.dart';
import 'package:feature_split/src/trips/trips_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('TripCard media stat chips refresh from stream provider', (
    tester,
  ) async {
    final controller =
        StreamController<({int photos, int notes, int receipts})>();
    addTearDown(controller.close);

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => TripCard(
            trip: const TripSummary(
              id: 'trip-1',
              name: 'Rome',
              baseCurrency: 'EUR',
            ),
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tripMediaCountsProvider('trip-1').overrideWith((ref) {
            return controller.stream;
          }),
          tripBalanceChipProvider('trip-1').overrideWith(
            (ref) => const AsyncValue.data(
              TripBalanceChipData(
                state: TripBalanceChipState.allSettled,
                label: 'All settled',
              ),
            ),
          ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light,
          routerConfig: router,
        ),
      ),
    );
    controller.add((photos: 4, notes: 2, receipts: 1));
    await tester.pump();
    await tester.pump();
    expect(find.text('4'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });
}
