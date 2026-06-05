import 'package:app_core/app_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('customSchemeLocationShape redacts token values', () {
    expect(
      customSchemeLocationShape(Uri.parse('app.vamo://join/-?token=secret')),
      'app.vamo://join/-?token=*',
    );
  });
}
