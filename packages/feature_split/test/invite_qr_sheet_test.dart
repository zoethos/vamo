import 'package:app_core/app_core.dart';
import 'invite_labels_test_support.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  testWidgets('QR encodes owned web invite link for token', (tester) async {
    const token = 'invite-token-42';
    final payload = InviteUrls.qrInvitePayload(token);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: QrImageView(
            data: payload,
            size: 120,
            backgroundColor: Colors.white,
          ),
        ),
      ),
    );

    expect(find.byType(QrImageView), findsOneWidget);
    expect(payload, 'https://vamo.world/j/invite-token-42');
  });

  test('invite labels bundle exposes scanner copy', () {
    expect(testInviteLabels.notVamoInvite, "That's not a Vamo invite");
  });
}
