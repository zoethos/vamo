import 'package:app_core/app_core.dart';
import 'package:feature_split/src/invites/invite_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  testWidgets('QR encodes app-scheme invite payload for token', (tester) async {
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
    expect(payload, 'app.vamo://join?token=invite-token-42');
  });

  test('invite labels bundle exposes scanner copy', () {
    const labels = InviteLabels(
      showQr: 'Show QR',
      scanQr: 'Scan a Vamo QR',
      qrCaption: 'Point a camera at this to join',
      notVamoInvite: "That's not a Vamo invite",
      cameraDenied: 'Camera denied',
      pasteLink: 'Paste invite link',
      pasteHint: 'https://vamo.app/j/…',
      pasteJoin: 'Join from link',
      scannerTitle: 'Scan invite QR',
    );
    expect(labels.notVamoInvite, "That's not a Vamo invite");
  });
}
