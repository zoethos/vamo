import 'package:url_launcher/url_launcher.dart';

/// Payment apps Vamo can hand off to (money never flows through Vamo).
enum PaymentMethod {
  venmo('venmo', 'Venmo'),
  paypal('paypal', 'PayPal'),
  wise('wise', 'Wise'),
  cash('cash', 'Cash');

  const PaymentMethod(this.id, this.label);
  final String id;
  final String label;
}

/// Methods shown for a trip — Venmo only when base currency is USD (Venmo is USD-only).
List<PaymentMethod> paymentMethodsForTrip(String tripBaseCurrency) {
  return [
    if (tripBaseCurrency == 'USD') PaymentMethod.venmo,
    PaymentMethod.paypal,
    PaymentMethod.wise,
    PaymentMethod.cash,
  ];
}

/// Explains what the handoff actually does (Wave 1 has no payee handles stored).
String paymentHandoffSubtitle({
  required PaymentMethod method,
  required String currency,
  required int cents,
}) {
  final amount = (cents / 100).toStringAsFixed(2);
  switch (method) {
    case PaymentMethod.venmo:
      return 'Opens Venmo with \$$amount prefilled — pick the recipient there';
    case PaymentMethod.paypal:
      return 'Opens PayPal.Me — amount is $amount $currency; you pick who receives it';
    case PaymentMethod.wise:
      return 'Opens Wise send flow — amount not prefilled';
    case PaymentMethod.cash:
      return 'Marks settled in Vamo only (no app link)';
  }
}

/// Best-effort deep link. Does not include payee handles (not stored in Wave 1).
Uri? paymentUri({
  required PaymentMethod method,
  required int cents,
  required String currency,
  String note = 'Vamo trip',
}) {
  if (method == PaymentMethod.cash) return null;
  if (method == PaymentMethod.venmo && currency != 'USD') return null;

  final amount = (cents / 100).toStringAsFixed(2);
  final encodedNote = Uri.encodeComponent(note);

  switch (method) {
    case PaymentMethod.venmo:
      return Uri.parse(
        'venmo://paycharge?txn=pay&amount=$amount&note=$encodedNote',
      );
    case PaymentMethod.paypal:
      return Uri.parse('https://www.paypal.com/paypalme/');
    case PaymentMethod.wise:
      return Uri.parse('https://wise.com/send');
    case PaymentMethod.cash:
      return null;
  }
}

/// Opens the payment app (or browser fallback). Returns whether a handler opened.
Future<bool> launchPaymentHandoff({
  required PaymentMethod method,
  required int cents,
  required String currency,
  String note = 'Vamo trip',
}) async {
  final uri = paymentUri(
    method: method,
    cents: cents,
    currency: currency,
    note: note,
  );
  if (uri == null) return false;

  if (await canLaunchUrl(uri)) {
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  if (method == PaymentMethod.venmo && currency == 'USD') {
    final web = Uri.parse(
      'https://account.venmo.com/pay?txn=pay&amount=${(cents / 100).toStringAsFixed(2)}&note=${Uri.encodeComponent(note)}',
    );
    if (await canLaunchUrl(web)) {
      return launchUrl(web, mode: LaunchMode.externalApplication);
    }
  }

  return false;
}
