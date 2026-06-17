import 'package:app_core/app_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('capturePhoto uses owner/trip/photo segments', () {
    expect(
      StoragePaths.capturePhoto(
        userId: 'u1',
        tripId: 't1',
        photoId: 'p1',
        ext: '.jpg',
      ),
      'u1/t1/p1.jpg',
    );
  });

  test('expenseReceipt uses four-segment receipts path', () {
    expect(
      StoragePaths.expenseReceipt(
        userId: 'u1',
        tripId: 't1',
        expenseId: 'e1',
        ext: 'png',
      ),
      'u1/t1/receipts/e1.png',
    );
  });

  test('captureVideo keeps owner and trip as first two segments', () {
    expect(
      StoragePaths.captureVideo(
        userId: 'u1',
        tripId: 't1',
        videoId: 'v1',
        ext: 'mp4',
      ),
      'u1/t1/videos/v1.mp4',
    );
  });
}
