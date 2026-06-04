import 'package:feature_split/feature_split.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('venmo URI only for USD trips', () {
    expect(
      paymentUri(
        method: PaymentMethod.venmo,
        cents: 3000,
        currency: 'EUR',
      ),
      isNull,
    );
    final uri = paymentUri(
      method: PaymentMethod.venmo,
      cents: 3000,
      currency: 'USD',
      note: 'Dinner',
    );
    expect(uri, isNotNull);
    expect(uri!.scheme, 'venmo');
    expect(uri.queryParameters['amount'], '30.00');
    expect(uri.queryParameters['note'], 'Dinner');
  });

  test('paypal opens generic PayPal.Me without broken amount path', () {
    final uri = paymentUri(
      method: PaymentMethod.paypal,
      cents: 3000,
      currency: 'EUR',
    );
    expect(uri!.path, '/paypalme/');
    expect(uri.queryParameters.containsKey('amount'), isFalse);
  });

  test('venmo hidden for non-USD in method list', () {
    expect(paymentMethodsForTrip('EUR'), isNot(contains(PaymentMethod.venmo)));
    expect(paymentMethodsForTrip('USD'), contains(PaymentMethod.venmo));
  });

  test('cash returns no URI', () {
    expect(
      paymentUri(
        method: PaymentMethod.cash,
        cents: 100,
        currency: 'EUR',
      ),
      isNull,
    );
  });
}
