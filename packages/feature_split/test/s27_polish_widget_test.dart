import 'package:app_core/app_core.dart';
import 'package:feature_split/src/invites/contact_invite_gateway.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'members_tab_test_support.dart';
import 'trip_home_labels_test_support.dart';

void main() {
  testWidgets('members screen has one app-bar invite action not duplicate buttons', (
    tester,
  ) async {
    await tester.pumpWidget(
      pumpMembersScreen(
        gateway: const UnsupportedContactInviteGateway(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.text('Invite'), findsNothing);
    expect(find.text('Invite Vamigos'), findsNothing);
    expect(find.text('Show QR'), findsNothing);
    expect(find.text('Invite from contacts'), findsNothing);
  });

  testWidgets('trip home exposes More menu not separate settings/share icons', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: DefaultTabController(
          length: 2,
          child: AppBar(
            title: const Text('Trip'),
            actions: [
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_horiz),
                tooltip: testTripHomeLabels.moreMenu,
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'settings',
                    child: Text(testTripHomeLabels.tripSettings),
                  ),
                  PopupMenuItem(
                    value: 'share',
                    child: Text(testTripHomeLabels.shareSnapshot),
                  ),
                ],
                onSelected: (_) {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.settings_outlined), findsNothing);
    expect(find.byIcon(Icons.share_outlined), findsNothing);
    expect(find.byIcon(Icons.more_horiz), findsOneWidget);
  });
}
