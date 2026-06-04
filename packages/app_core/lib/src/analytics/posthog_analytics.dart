import 'package:flutter/foundation.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

import '../env/env.dart';
import 'analytics.dart';

/// Initializes PostHog when [Env.posthogApiKey] is set. Call once before [runApp].
Future<void> initPostHog() async {
  final key = Env.posthogApiKey;
  if (key.isEmpty) return;

  final config = PostHogConfig(key);
  config.host = Env.posthogHost;
  config.debug = kDebugMode;
  await Posthog().setup(config);
}

class PosthogAnalytics implements Analytics {
  @override
  void capture(VamoEvent event, {Map<String, Object?> properties = const {}}) {
    final props = properties.isEmpty
        ? null
        : Map<String, Object>.from(properties);
    Posthog().capture(eventName: event.name, properties: props);
  }

  @override
  Future<void> identify(String userId) {
    return Posthog().identify(userId: userId);
  }

  @override
  Future<void> reset() {
    return Posthog().reset();
  }
}
