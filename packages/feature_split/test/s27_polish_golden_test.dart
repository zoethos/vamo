import 'package:feature_split/src/invites/contact_invite_gateway.dart';
import 'package:feature_split/src/trips/members_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_test_theme.dart';
import 'members_tab_test_support.dart';

/// Android small-screen goldens for S27 polish (360×640 logical).
void main() {
  const surface = Size(360, 640);

  testWidgets('members invite single action small screen golden', (
    tester,
  ) async {
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      pumpMembersTab(
        gateway: const UnsupportedContactInviteGateway(),
        theme: goldenTestTheme(),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MembersTab),
      matchesGoldenFile('goldens/s27_members_invite_small.png'),
    );
  });

  testWidgets('trip more menu app bar small screen golden', (tester) async {
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: goldenTestTheme(),
        home: DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Amalfi crew'),
              leading: const BackButton(),
              actions: [
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_horiz),
                  tooltip: 'More',
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'settings',
                      child: Text('Trip settings'),
                    ),
                    PopupMenuItem(
                      value: 'share',
                      child: Text('Share snapshot'),
                    ),
                  ],
                  onSelected: (_) {},
                ),
              ],
              bottom: const TabBar(
                tabs: [
                  Tab(text: 'Expenses'),
                  Tab(text: 'Plan'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(AppBar),
      matchesGoldenFile('goldens/s27_trip_appbar_small.png'),
    );
  });
}
