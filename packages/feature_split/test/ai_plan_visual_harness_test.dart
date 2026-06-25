import 'dart:io';

import 'package:feature_split/src/plan/plan_models.dart';
import 'package:feature_split/src/travel/route_draft.dart';
import 'package:feature_split/src/travel/route_draft_review_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_test_theme.dart';
import 'travel_test_support.dart';

void main() {
  testWidgets('AI proposal review matches the reference state', (tester) async {
    await _loadMaterialIcons();

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: goldenTestTheme(),
          home: RouteDraftReviewScreen(
            tripId: 'trip-1',
            title: 'Summer on the Amalfi Coast',
            subtitle: 'Amalfi, Italy · May 12–18 · 6 days',
            draft: _proposalDraft,
            labels: advancedTravelTestLabels,
            initiallySkippedIndexes: const {3, 6, 7, 8, 9, 10, 11},
          ),
        ),
      ),
    );
    await tester.pump();

    await expectLater(
      find.byType(RouteDraftReviewScreen),
      matchesGoldenFile(
        Platform.isLinux
            ? 'goldens/route_draft_review_ai_plan_linux.png'
            : 'goldens/route_draft_review_ai_plan.png',
      ),
    );
  });
}

var _materialIconsLoaded = false;

Future<void> _loadMaterialIcons() async {
  if (_materialIconsLoaded) return;
  final flutterRoot = _flutterRoot();
  final font = File(
    '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (!font.existsSync()) {
    throw StateError('Missing MaterialIcons font: ${font.path}');
  }
  final loader = FontLoader('MaterialIcons');
  loader.addFont(Future.value(ByteData.view(font.readAsBytesSync().buffer)));
  await loader.load();
  _materialIconsLoaded = true;
}

String _flutterRoot() {
  final fromEnv = Platform.environment['FLUTTER_ROOT'];
  if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 5; i++) {
    dir = dir.parent;
  }
  return dir.path;
}

final _proposalDraft = RouteDraft(
  draftId: 'draft-1',
  warnings: [],
  unresolvedQuestions: [],
  items: [
    RouteDraftItem(
      kind: PlanItemKind.lodging,
      title: 'Check-in at Hotel Marina Riviera',
      notes: 'Lodging · Amalfi',
      startsAt: DateTime(2026, 5, 12),
    ),
    RouteDraftItem(
      kind: PlanItemKind.visit,
      title: 'Piazza Duomo',
      notes: 'Historic piazza · Amalfi',
      startsAt: DateTime(2026, 5, 12),
    ),
    RouteDraftItem(
      kind: PlanItemKind.activity,
      title: 'Path of the Gods hike',
      notes: 'Hike · Bomerano',
      startsAt: DateTime(2026, 5, 13),
    ),
    RouteDraftItem(
      kind: PlanItemKind.other,
      title: 'Lunch in Nocelle',
      notes: 'Restaurant · Local cuisine',
      startsAt: DateTime(2026, 5, 13),
    ),
    RouteDraftItem(
      kind: PlanItemKind.transfer,
      title: 'Ferry to Positano',
      notes: 'Transport · Amalfi → Positano',
      transferSubtype: TransferSubtype.transit,
      startsAt: DateTime(2026, 5, 13),
    ),
    RouteDraftItem(
      kind: PlanItemKind.visit,
      title: 'Villa Rufolo',
      notes: 'Historic villa & gardens · Ravello',
      startsAt: DateTime(2026, 5, 14),
    ),
    RouteDraftItem(
      kind: PlanItemKind.other,
      title: 'Dinner in Ravello',
      notes: 'Restaurant · Fine dining',
      startsAt: DateTime(2026, 5, 14),
    ),
    RouteDraftItem(
      kind: PlanItemKind.visit,
      title: 'Minori lemon walk',
      notes: 'Walk · Minori',
      startsAt: DateTime(2026, 5, 15),
    ),
    RouteDraftItem(
      kind: PlanItemKind.transfer,
      title: 'Boat to Capri',
      notes: 'Transport · Amalfi → Capri',
      startsAt: DateTime(2026, 5, 16),
    ),
    RouteDraftItem(
      kind: PlanItemKind.visit,
      title: 'Gardens of Augustus',
      notes: 'Garden · Capri',
      startsAt: DateTime(2026, 5, 16),
    ),
    RouteDraftItem(
      kind: PlanItemKind.activity,
      title: 'Sunset swim at Atrani',
      notes: 'Activity · Atrani',
      startsAt: DateTime(2026, 5, 17),
    ),
    RouteDraftItem(
      kind: PlanItemKind.visit,
      title: 'Ravello ceramic studios',
      notes: 'Shopping · Ravello',
      startsAt: DateTime(2026, 5, 18),
    ),
  ],
);
