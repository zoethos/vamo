import 'package:app_core/app_core.dart';

import 'package:drift/native.dart';

import 'package:feature_split/src/capture/capture_action_sheet.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:supabase_flutter/supabase_flutter.dart';



void main() {

  Future<void> pumpSheet(WidgetTester tester) async {

    final db = AppDatabase.forTesting(NativeDatabase.memory());

    addTearDown(db.close);

    final client = SupabaseClient(

      'http://localhost',

      'anon-key',

      authOptions: const AuthClientOptions(autoRefreshToken: false),

    );



    await tester.pumpWidget(

      ProviderScope(

        overrides: [

          appDatabaseProvider.overrideWithValue(db),

          supabaseClientProvider.overrideWithValue(client),

          analyticsProvider.overrideWithValue(DebugAnalytics()),

        ],

        child: MaterialApp(

          theme: AppTheme.light,

          home: Builder(

            builder: (context) => Scaffold(

              body: Center(

                child: FilledButton(

                  onPressed: () => showCaptureActionSheet(

                    context: context,

                    tripId: 'trip-1',

                  ),

                  child: const Text('Open'),

                ),

              ),

            ),

          ),

        ),

      ),

    );

    await tester.pumpAndSettle();



    await tester.tap(find.text('Open'));

    await tester.pumpAndSettle();

  }



  testWidgets('capture choice sheet shows carousel with centered noun label',

      (tester) async {

    await pumpSheet(tester);



    expect(find.byType(PageView), findsOneWidget);

    expect(find.byType(CaptureChoiceSheet), findsOneWidget);

    expect(find.text('Photo'), findsOneWidget);

    expect(find.text('Add note'), findsNothing);

    expect(find.text('Add photo'), findsNothing);

  });



  testWidgets('capture carousel exposes semantic labels for every option',

      (tester) async {

    await pumpSheet(tester);



    for (final label in ['Photo', 'Video', 'Note', 'Background']) {
      expect(find.bySemanticsLabel(label), findsOneWidget);
    }

  });



  testWidgets('semantic options are buttons reachable without scrolling',
      (tester) async {
    await pumpSheet(tester);

    for (final label in ['Photo', 'Video', 'Note', 'Background']) {
      final data =
          tester.getSemantics(find.bySemanticsLabel(label)).getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
    }
  });

}


