import 'package:app_core/app_core.dart';
import 'package:feature_split/src/plan/plan_models.dart';
import 'package:feature_split/src/travel/route_draft.dart';
import 'package:feature_split/src/travel/route_draft_review_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'travel_test_support.dart';

Map<String, Object?> _payload() => {
      'ok': true,
      'draft': {
        'draft_id': 'd1',
        'plan_items': [
          {
            'kind': 'transfer',
            'title': 'Drive to Positano',
            'starts_at': '2026-07-01',
            'ends_at': '2026-07-01',
            'transfer_subtype': 'drive',
            'leg_index': 0,
            'notes': null,
          },
          {
            'kind': 'visit',
            'title': 'Villa Rufolo',
            'starts_at': '2026-07-02',
            'ends_at': null,
            'transfer_subtype': null,
            'leg_index': null,
            'notes': 'Gardens',
          },
          // Invalid: empty title → dropped.
          {'kind': 'train', 'title': '   '},
        ],
        'warnings': ['Bike leg is tight on Jul 5'],
        'unresolved_questions': ['Hotel in Positano or Amalfi town?'],
      },
    };

void main() {
  group('RouteDraft.fromPayload', () {
    test('parses items, drops invalid, keeps warnings + questions', () {
      final draft = RouteDraft.fromPayload(_payload());
      expect(draft, isNotNull);
      expect(draft!.draftId, 'd1');
      expect(draft.items.length, 2); // empty-title item dropped
      expect(draft.warnings.single, contains('Bike leg'));
      expect(draft.unresolvedQuestions.single, contains('Hotel'));
    });

    test('returns null when the payload has no draft', () {
      expect(RouteDraft.fromPayload({'ok': true}), isNull);
      expect(RouteDraft.fromPayload('nope'), isNull);
    });
  });

  group('RouteDraftItem.toPlanItemInput', () {
    test('transfer carries its subtype as metadata', () {
      final draft = RouteDraft.fromPayload(_payload())!;
      final input = draft.items.first.toPlanItemInput('trip-1');
      expect(input.kind, PlanItemKind.transfer);
      expect(input.title, 'Drive to Positano');
      expect(input.metadata['subtype'], TransferSubtype.drive.wireName);
      expect(input.startsAt, DateTime(2026, 7, 1));
    });

    test('non-transfer keeps notes, no metadata', () {
      final draft = RouteDraft.fromPayload(_payload())!;
      final visit = draft.items[1].toPlanItemInput('trip-1');
      expect(visit.kind, PlanItemKind.visit);
      expect(visit.notes, 'Gardens');
      expect(visit.metadata, isEmpty);
      expect(visit.endsAt, isNull);
    });
  });

  group('RouteDraftReviewScreen', () {
    Future<void> pump(
      WidgetTester tester,
      RouteDraft draft, {
      Set<int> initiallySkippedIndexes = const <int>{},
      RouteDraftCommitOverride? commitOverride,
    }) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light,
            home: RouteDraftReviewScreen(
              tripId: 'trip-1',
              title: 'Summer on the Amalfi Coast',
              subtitle: 'Amalfi, Italy · May 12–18 · 6 days',
              draft: draft,
              labels: advancedTravelTestLabels,
              initiallySkippedIndexes: initiallySkippedIndexes,
              commitOverride: commitOverride,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('renders the reference proposal state', (
      tester,
    ) async {
      await pump(
        tester,
        _proposalDraft,
        initiallySkippedIndexes: const {3, 6, 7, 8, 9, 10, 11},
      );

      expect(find.text('Summer on the Amalfi Coast'), findsOneWidget);
      expect(find.text('Amalfi, Italy · May 12–18 · 6 days'), findsOneWidget);
      expect(find.text('AI backdrop'), findsOneWidget);
      expect(
        find.text(
          'AI found 12 stops worth visiting.\n'
          'Keep what you like — skip the rest.',
        ),
        findsOneWidget,
      );
      expect(find.text('5 of 12 kept'), findsOneWidget);
      expect(find.text('Create trip · 5 stops'), findsOneWidget);
      expect(find.text('DAY 1 · MAY 12'), findsOneWidget);
      expect(find.text('Check-in at Hotel Marina Riviera'), findsOneWidget);
      expect(find.text('Lunch in Nocelle'), findsOneWidget);
      expect(find.text('Dinner in Ravello'), findsOneWidget);
    });

    testWidgets('toggles rows and keep/skip all update the CTA', (
      tester,
    ) async {
      await pump(
        tester,
        _proposalDraft,
        initiallySkippedIndexes: const {3, 6, 7, 8, 9, 10, 11},
      );

      await tester.tap(find.text('Lunch in Nocelle'));
      await tester.pump();

      expect(find.text('6 of 12 kept'), findsOneWidget);
      expect(find.text('Create trip · 6 stops'), findsOneWidget);

      await tester.tap(find.text('Skip all'));
      await tester.pump();

      expect(find.text('0 of 12 kept'), findsOneWidget);
      expect(find.text('Create empty trip'), findsOneWidget);

      await tester.tap(find.text('Keep all'));
      await tester.pump();

      expect(find.text('12 of 12 kept'), findsOneWidget);
      expect(find.text('Create trip · 12 stops'), findsOneWidget);
    });

    testWidgets('warnings and questions still render below draft rows', (
      tester,
    ) async {
      await pump(tester, RouteDraft.fromPayload(_payload())!);

      expect(find.text('Villa Rufolo'), findsOneWidget);
      expect(find.text('Heads up'), findsOneWidget); // warnings block
      expect(find.text('Open questions'), findsOneWidget);
      expect(find.text('2 of 2 kept'), findsOneWidget);
    });

    testWidgets('commit passes kept stops in visible order', (tester) async {
      List<RouteDraftItem>? committed;
      await pump(
        tester,
        _proposalDraft,
        initiallySkippedIndexes: const {1, 3, 6},
        commitOverride: (items) async => committed = items,
      );

      await tester.tap(find.text('Create trip · 9 stops'));
      await tester.pumpAndSettle();

      expect(committed, isNotNull);
      expect(committed!.map((item) => item.title), [
        'Check-in at Hotel Marina Riviera',
        'Path of the Gods hike',
        'Ferry to Positano',
        'Villa Rufolo',
        'Minori lemon walk',
        'Boat to Capri',
        'Gardens of Augustus',
        'Sunset swim at Atrani',
        'Ravello ceramic studios',
      ]);
    });

    testWidgets('start empty bypasses commit override', (tester) async {
      var committed = false;
      await pump(
        tester,
        _proposalDraft,
        commitOverride: (_) async => committed = true,
      );

      await tester.tap(find.text('start empty'));
      await tester.pumpAndSettle();

      expect(committed, isFalse);
    });

    testWidgets('empty draft shows the empty message', (tester) async {
      await pump(
        tester,
        const RouteDraft(
          draftId: 'x',
          items: [],
          warnings: [],
          unresolvedQuestions: [],
        ),
      );
      expect(find.text('No stops were drafted.'), findsOneWidget);
      expect(find.text('Create empty trip'), findsOneWidget);
    });
  });
}

final _proposalDraft = RouteDraft(
  draftId: 'draft-1',
  warnings: const [],
  unresolvedQuestions: const [],
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
