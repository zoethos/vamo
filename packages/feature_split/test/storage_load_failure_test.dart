import 'package:app_core/app_core.dart';
import 'package:drift/native.dart';
import 'package:feature_split/src/capture/capture_tab.dart';
import 'package:feature_split/src/capture/capture_models.dart';
import 'package:feature_split/src/expenses/trip_expense_list_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:feature_split/src/expenses/expense_models.dart';
import 'package:feature_split/src/expenses/expenses_repository.dart';

void main() {
  group('storage load failures', () {
    testWidgets('receipt 403 shows placeholder and reports auth failure',
        (tester) async {
      final events = <Map<String, Object?>>[];
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final queue = SyncQueue(db);
      final client = SupabaseClient(
        'http://localhost',
        'anon-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      final repo = _StubExpensesRepository(
        db: db,
        queue: queue,
        client: client,
        loadResult: StorageAttachmentLoadResult.failure(
          const StorageException('Forbidden', statusCode: '403'),
          hadRemoteAttachment: true,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            analyticsProvider.overrideWithValue(_RecordingAnalytics(events)),
            expensesRepositoryProvider.overrideWith((ref) => repo),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: TripExpenseListTile(
                description: 'Dinner',
                payer: 'Alex',
                spentAt: DateTime(2026, 6, 2),
                baseCents: 3000,
                amountCents: 3000,
                tripBaseCurrency: 'EUR',
                expenseCurrency: 'EUR',
                expenseId: 'e1',
                tripId: 't1',
                receiptPath: 'u1/t1/receipts/e1.jpg',
                proposalRowPrefix: 'Proposal',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(StorageUnavailablePlaceholder), findsOneWidget);
      expect(events, [
        {
          'event': VamoEvent.actionFailed,
          'properties': {
            'screen': 'trip_home',
            'action': 'load_receipt',
            'severity': 'failure',
            'error_kind': 'auth',
            'error_code': 'storage_403',
          },
        },
      ]);
    });

    testWidgets('photo 403 shows placeholder and reports auth failure',
        (tester) async {
      final events = <Map<String, Object?>>[];
      final photo = TripPhotoView(
        id: 'p1',
        tripId: 't1',
        displayPath: null,
        capturedAt: DateTime(2026, 6, 2),
        loadError: const StorageException('Forbidden', statusCode: '403'),
        hasRemoteStoragePath: true,
        storagePath: 'u1/t1/p1.jpg',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            analyticsProvider.overrideWithValue(_RecordingAnalytics(events)),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: CapturePhotoCell(tripId: 't1', photo: photo),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(StorageUnavailablePlaceholder), findsOneWidget);
      expect(events, [
        {
          'event': VamoEvent.actionFailed,
          'properties': {
            'screen': 'trip_home',
            'action': 'load_photo',
            'severity': 'failure',
            'error_kind': 'auth',
            'error_code': 'storage_403',
          },
        },
      ]);
    });

    testWidgets('video 403 shows placeholder and reports auth failure',
        (tester) async {
      final events = <Map<String, Object?>>[];
      final video = TripVideoView(
        id: 'v1',
        tripId: 't1',
        displayPath: null,
        capturedAt: DateTime(2026, 6, 2),
        loadError: const StorageException('Forbidden', statusCode: '403'),
        hasRemoteStoragePath: true,
        storagePath: 'u1/t1/videos/v1.mp4',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            analyticsProvider.overrideWithValue(_RecordingAnalytics(events)),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: CaptureVideoCell(tripId: 't1', video: video),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(StorageUnavailablePlaceholder), findsOneWidget);
      expect(events, [
        {
          'event': VamoEvent.actionFailed,
          'properties': {
            'screen': 'trip_home',
            'action': 'load_video',
            'severity': 'failure',
            'error_kind': 'auth',
            'error_code': 'storage_403',
          },
        },
      ]);
    });
  });
}

class _StubExpensesRepository extends ExpensesRepository {
  _StubExpensesRepository({
    required AppDatabase db,
    required SyncQueue queue,
    required SupabaseClient client,
    required this.loadResult,
  }) : super(
          db: db,
          client: client,
          analytics: DebugAnalytics(),
          fxRates: FxRatesClient(),
          syncQueue: queue,
          syncWorker: SyncWorker(
            queue: queue,
            client: client,
            flushWithoutSession: true,
            testExecute: (_) async {},
          ),
        );

  final StorageAttachmentLoadResult loadResult;

  @override
  Future<StorageAttachmentLoadResult> loadReceiptAttachment(
    ExpenseSummary expense,
  ) async =>
      loadResult;
}

class _RecordingAnalytics implements Analytics {
  _RecordingAnalytics(this.events);

  final List<Map<String, Object?>> events;

  @override
  void capture(VamoEvent event, {Map<String, Object?> properties = const {}}) {
    events.add({'event': event, 'properties': properties});
  }

  @override
  Future<void> identify(String userId) async {}

  @override
  Future<void> reset() async {}
}
