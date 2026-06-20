import 'package:app_core/src/env/env.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('optional settings fall back when dotenv has not been loaded', () {
    expect(Env.posthogApiKey, '');
    expect(Env.posthogHost, 'https://eu.i.posthog.com');
    expect(Env.fxRatesFunctionUrl, '');
    expect(Env.exchangerateAccessKey, '');
  });

  test('required settings still fail loudly when dotenv has not been loaded',
      () {
    expect(
      () => Env.supabaseUrl,
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('SUPABASE_URL'),
        ),
      ),
    );
  });
}
