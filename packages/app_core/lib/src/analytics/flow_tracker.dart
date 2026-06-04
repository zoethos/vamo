import 'analytics.dart';

/// Tracks a multi-step flow; fires [VamoEvent.flowAbandoned] on dispose if not completed.
class FlowTracker {
  FlowTracker({
    required this.flow,
    required Analytics analytics,
  })  : _analytics = analytics,
        _started = DateTime.now();

  final String flow;
  final Analytics _analytics;
  final DateTime _started;
  bool _completed = false;

  void complete() => _completed = true;

  void abandonIfIncomplete() {
    if (_completed) return;
    _analytics.capture(
      VamoEvent.flowAbandoned,
      properties: {
        'flow': flow,
        'elapsed_ms': DateTime.now().difference(_started).inMilliseconds,
      },
    );
  }
}
