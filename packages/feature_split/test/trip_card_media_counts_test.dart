import 'package:app_core/app_core.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('watchTripMediaCounts emits live updates', () async {
    const tripId = 'trip-1';
    final created = DateTime.utc(2026, 1, 1);
    await db.upsertTrip(
      LocalTripsCompanion(
        id: const Value(tripId),
        name: const Value('Rome'),
        baseCurrency: const Value('EUR'),
        ownerId: const Value('u1'),
        createdAt: Value(created),
        updatedAt: Value(created),
      ),
    );

    final counts = <({int photos, int notes, int receipts})>[];
    final sub = db.watchTripMediaCounts(tripId).listen(counts.add);
    await Future<void>.delayed(Duration.zero);
    expect(counts.last, (photos: 0, notes: 0, receipts: 0));

    await db.upsertTripPhoto(
      LocalTripPhotosCompanion(
        id: const Value('p1'),
        tripId: const Value(tripId),
        localPath: const Value('/tmp/p1.jpg'),
        capturedAt: Value(created),
        createdBy: const Value('u1'),
        createdAt: Value(created),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(counts.last.photos, 1);

    await db.upsertExpense(
      LocalExpensesCompanion(
        id: const Value('e1'),
        tripId: const Value(tripId),
        description: const Value('Lunch'),
        amountCents: const Value(1200),
        baseCents: const Value(1200),
        currency: const Value('EUR'),
        payerId: const Value('u1'),
        fxRate: const Value(1.0),
        spentAt: Value(created),
        createdBy: const Value('u1'),
        createdAt: Value(created),
        localReceiptPath: const Value('/tmp/receipt.jpg'),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(counts.last.receipts, 1);

    await sub.cancel();
  });
}
