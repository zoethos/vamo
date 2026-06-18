import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('offloadTripMediaCache drops remote-backed files only', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final temp = await Directory.systemTemp.createTemp('vamo-offload-test-');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    Future<String> file(String name) async {
      final path = '${temp.path}${Platform.pathSeparator}$name';
      await File(path).writeAsString(name);
      return path;
    }

    final backgroundPath = await file('background.jpg');
    final remotePhotoPath = await file('remote-photo.jpg');
    final localPhotoPath = await file('local-photo.jpg');
    final remoteVideoPath = await file('remote-video.mp4');
    final localVideoPath = await file('local-video.mp4');
    final remoteReceiptPath = await file('remote-receipt.jpg');
    final localReceiptPath = await file('local-receipt.jpg');

    final now = DateTime.utc(2026, 6, 19);
    await db.upsertTrip(
      LocalTripsCompanion(
        id: const Value('trip-1'),
        name: const Value('Amalfi'),
        ownerId: const Value('owner-1'),
        baseCurrency: const Value('EUR'),
        backgroundPath: const Value('u/trip-1/background.jpg'),
        backgroundLocalPath: Value(backgroundPath),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    await db.upsertTripPhoto(
      LocalTripPhotosCompanion(
        id: const Value('photo-remote'),
        tripId: const Value('trip-1'),
        localPath: Value(remotePhotoPath),
        storagePath: const Value('u/trip-1/photos/remote.jpg'),
        capturedAt: Value(now),
        createdBy: const Value('owner-1'),
        createdAt: Value(now),
      ),
    );
    await db.upsertTripPhoto(
      LocalTripPhotosCompanion(
        id: const Value('photo-local'),
        tripId: const Value('trip-1'),
        localPath: Value(localPhotoPath),
        capturedAt: Value(now),
        createdBy: const Value('owner-1'),
        createdAt: Value(now),
      ),
    );
    await db.upsertTripVideo(
      LocalTripVideosCompanion(
        id: const Value('video-remote'),
        tripId: const Value('trip-1'),
        localPath: Value(remoteVideoPath),
        storagePath: const Value('u/trip-1/videos/remote.mp4'),
        capturedAt: Value(now),
        createdBy: const Value('owner-1'),
        createdAt: Value(now),
      ),
    );
    await db.upsertTripVideo(
      LocalTripVideosCompanion(
        id: const Value('video-local'),
        tripId: const Value('trip-1'),
        localPath: Value(localVideoPath),
        capturedAt: Value(now),
        createdBy: const Value('owner-1'),
        createdAt: Value(now),
      ),
    );
    await db.upsertExpense(
      LocalExpensesCompanion(
        id: const Value('expense-remote'),
        tripId: const Value('trip-1'),
        payerId: const Value('owner-1'),
        amountCents: const Value(1200),
        currency: const Value('EUR'),
        baseCents: const Value(1200),
        fxRate: const Value(1),
        description: const Value('Lunch'),
        spentAt: Value(now),
        createdBy: const Value('owner-1'),
        createdAt: Value(now),
        receiptPath: const Value('u/trip-1/receipts/remote.jpg'),
        localReceiptPath: Value(remoteReceiptPath),
      ),
    );
    await db.upsertExpense(
      LocalExpensesCompanion(
        id: const Value('expense-local'),
        tripId: const Value('trip-1'),
        payerId: const Value('owner-1'),
        amountCents: const Value(900),
        currency: const Value('EUR'),
        baseCents: const Value(900),
        fxRate: const Value(1),
        description: const Value('Coffee'),
        spentAt: Value(now),
        createdBy: const Value('owner-1'),
        createdAt: Value(now),
        localReceiptPath: Value(localReceiptPath),
      ),
    );

    final result = await db.offloadTripMediaCache('trip-1');

    expect(result.backgrounds, 1);
    expect(result.photos, 1);
    expect(result.videos, 1);
    expect(result.receipts, 1);

    expect(await File(backgroundPath).exists(), isFalse);
    expect(await File(remotePhotoPath).exists(), isFalse);
    expect(await File(remoteVideoPath).exists(), isFalse);
    expect(await File(remoteReceiptPath).exists(), isFalse);
    expect(await File(localPhotoPath).exists(), isTrue);
    expect(await File(localVideoPath).exists(), isTrue);
    expect(await File(localReceiptPath).exists(), isTrue);

    final trip = await db.watchTrip('trip-1').first;
    expect(trip?.backgroundLocalPath, isNull);

    final photos = await db.watchTripPhotos('trip-1').first;
    expect(
      photos.singleWhere((p) => p.id == 'photo-remote').localPath,
      isNull,
    );
    expect(
      photos.singleWhere((p) => p.id == 'photo-local').localPath,
      localPhotoPath,
    );

    final videos = await db.watchTripVideos('trip-1').first;
    expect(
      videos.singleWhere((v) => v.id == 'video-remote').localPath,
      isNull,
    );
    expect(
      videos.singleWhere((v) => v.id == 'video-local').localPath,
      localVideoPath,
    );

    final expenses = await db.watchTripExpenses('trip-1').first;
    expect(
      expenses.singleWhere((e) => e.id == 'expense-remote').localReceiptPath,
      isNull,
    );
    expect(
      expenses.singleWhere((e) => e.id == 'expense-local').localReceiptPath,
      localReceiptPath,
    );
  });
}
