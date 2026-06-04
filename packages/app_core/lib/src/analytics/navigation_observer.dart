import 'package:flutter/material.dart';

import 'analytics.dart';

/// Fires [VamoEvent.screenViewed] when a named route is pushed.
class VamoNavigationObserver extends NavigatorObserver {
  VamoNavigationObserver(this._analytics);

  final Analytics _analytics;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _capture(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (newRoute != null) _capture(newRoute);
  }

  void _capture(Route<dynamic> route) {
    final name = route.settings.name;
    if (name == null || name.isEmpty) return;
    _analytics.capture(
      VamoEvent.screenViewed,
      properties: {'screen': name},
    );
  }
}
