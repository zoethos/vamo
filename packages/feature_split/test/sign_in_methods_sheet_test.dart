import 'package:app_core/app_core.dart';
import 'package:feature_split/src/profile/sign_in_methods_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('explains when manual identity linking is unavailable', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SignInMethodsSheet(
            linkedProviders: const {AuthIdentityProvider.email},
            onLink: (_) async => throw const IdentityLinkUnavailableException(),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Link').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(
      find.text('Adding a sign-in method is not enabled yet. Try again later.'),
      findsOneWidget,
    );
  });
}
