import 'package:app_core/app_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// Locks North-Star (criterion 6) and product-signal events (criterion 7).
void main() {
  test('VamoEvent.northStar lists exactly seven funnel events', () {
    expect(VamoEvent.northStar, hasLength(7));
    expect(
      VamoEvent.northStar.map((e) => e.name).toSet(),
      equals({
        'trip_created',
        'member_invited',
        'invite_accepted',
        'expense_added',
        'settle_marked',
        'settle_confirmed',
        'snapshot_shared',
      }),
    );
  });

  test('VamoEvent.productSignals lists layer 2–4 events', () {
    expect(VamoEvent.productSignals, hasLength(12));
    expect(
      VamoEvent.productSignals.map((e) => e.name),
      containsAll([
        'screen_viewed',
        'error_shown',
        'empty_state_shown',
        'flow_abandoned',
        'action_failed',
        'plus_interest_tapped',
        'recap_interest_tapped',
        'map_interest_tapped',
        'notify_me_opted_in',
        'suggestion_submitted',
        'ocr_suggestion_edited',
        'place_resolved',
      ]),
    );
  });

  test('DebugAnalytics captures without throwing', () {
    final analytics = DebugAnalytics();
    for (final event in VamoEvent.values) {
      expect(() => analytics.capture(event), returnsNormally);
    }
  });
}
