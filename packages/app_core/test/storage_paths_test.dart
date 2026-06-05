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
}
