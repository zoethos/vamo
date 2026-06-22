import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Visit RSVP migration aligns RPC guards and capability seed', () {
    final source = File(
      '../../supabase/migrations/20260622161731_visit_rsvp_capability.sql',
    ).readAsStringSync();

    expect(
      source,
      contains(
        "v_kind not in ('activity'::plan_item_kind, 'visit'::plan_item_kind)",
      ),
    );
    expect(source, isNot(contains("v_kind <> 'activity'::plan_item_kind")));
    expect(
      source,
      contains("('visit', 2, true, true, false, false, false, true)"),
    );
    expect(source, contains('grant execute on function set_event_rsvp'));
    expect(source, contains('grant execute on function clear_event_rsvp'));
  });
}
