import 'package:app_core/app_core.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingAnalytics implements Analytics {
  final captured = <VamoEvent>[];

  @override
  void capture(VamoEvent event, {Map<String, Object?> properties = const {}}) {
    captured.add(event);
  }

  @override
  Future<void> identify(String userId) async {}

  @override
  Future<void> reset() async {}
}

void main() {
  test('FlowTracker fires flowAbandoned when not completed', () {
    final analytics = _RecordingAnalytics();
    final tracker = FlowTracker(flow: 'add_expense', analytics: analytics);
    tracker.abandonIfIncomplete();
    expect(analytics.captured, [VamoEvent.flowAbandoned]);
  });

  test('FlowTracker does not fire after complete', () {
    final analytics = _RecordingAnalytics();
    final tracker = FlowTracker(flow: 'create_trip', analytics: analytics);
    tracker.complete();
    tracker.abandonIfIncomplete();
    expect(analytics.captured, isEmpty);
  });
}
