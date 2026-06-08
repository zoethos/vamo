import 'package:feature_split/src/invites/contact_invite_gateway.dart';
import 'package:feature_split/src/trips/trip_members_screen.dart';
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
      pumpMembersScreen(
        gateway: const UnsupportedContactInviteGateway(),
        theme: goldenTestTheme(),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(TripMembersScreen),
      matchesGoldenFile('goldens/s27_members_invite_small.png'),
    );
  });

  testWidgets('expenses list header add small screen golden', (tester) async {
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: goldenTestTheme(),
        home: Scaffold(
          appBar: AppBar(
            title: const Text('Expenses'),
            actions: [
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'Add expense',
                onPressed: () {},
              ),
            ],
          ),
          body: const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(AppBar),
      matchesGoldenFile('goldens/s27_expenses_header_small.png'),
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
        home: Scaffold(
          appBar: AppBar(
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
          ),
          body: const SizedBox.shrink(),
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
