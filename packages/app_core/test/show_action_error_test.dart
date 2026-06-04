import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets('PostgrestException snackbar hides raw server details', (tester) async {
    final events = <Map<String, Object?>>[];
    const rawMessage = 'Could not find the function public.create_trip';

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          analyticsProvider.overrideWithValue(_RecordingAnalytics(events)),
        ],
        child: const MaterialApp(home: _ShowErrorHarness()),
      ),
    );

    await tester.tap(find.text('fail'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final snackText = tester.widget<SnackBar>(find.byType(SnackBar)).content
        as Text;
    final shown = snackText.data!;

    expect(shown.toLowerCase(), isNot(contains('postgrest')));
    expect(shown.toUpperCase(), isNot(contains('PGRST')));
    expect(shown, isNot(contains(rawMessage)));

    expect(events, [
      {
        'event': VamoEvent.actionFailed,
        'properties': {
          'screen': 'create_trip',
          'action': 'create_trip',
          'kind': 'server',
          'code': 'PGRST202',
        },
      },
    ]);
  });

  test('maps OTP AuthException to friendly copy', () {
    expect(
      actionFailureUserMessage(
        const AuthException('Token has expired or is invalid', code: 'otp_expired'),
      ),
      "That code didn't match — try again",
    );
  });

  test('maps flow-state AuthException to cross-device copy', () {
    expect(
      actionFailureUserMessage(
        const AuthException('flow state not found', code: 'flow_state_not_found'),
      ),
      'This link was for a different device — use the 6-digit code',
    );
  });
}

class _ShowErrorHarness extends ConsumerWidget {
  const _ShowErrorHarness();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () => showActionError(
            context,
            ref,
            screen: 'create_trip',
            action: 'create_trip',
            error: const PostgrestException(
              message: 'Could not find the function public.create_trip',
              code: 'PGRST202',
            ),
          ),
          child: const Text('fail'),
        ),
      ),
    );
  }
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
