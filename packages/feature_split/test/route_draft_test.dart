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
    Future<void> pump(WidgetTester tester, RouteDraft draft) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light,
            home: RouteDraftReviewScreen(
              tripId: 'trip-1',
              draft: draft,
              labels: advancedTravelTestLabels,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('renders stops + notes; accept count starts at all', (
      tester,
    ) async {
      await pump(tester, RouteDraft.fromPayload(_payload())!);

      expect(find.text('Drive to Positano'), findsOneWidget);
      expect(find.text('Villa Rufolo'), findsOneWidget);
      expect(find.text('Heads up'), findsOneWidget); // warnings block
      expect(find.text('Open questions'), findsOneWidget);
      expect(find.text('Add to plan (2)'), findsOneWidget);
    });

    testWidgets('unchecking a stop lowers the accept count', (tester) async {
      await pump(tester, RouteDraft.fromPayload(_payload())!);

      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.pump();

      expect(find.text('Add to plan (1)'), findsOneWidget);
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
    });
  });
}
