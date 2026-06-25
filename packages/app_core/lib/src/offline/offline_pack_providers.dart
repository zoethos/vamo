import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../analytics/action_failure.dart';
import '../analytics/analytics.dart';
import '../analytics/analytics_providers.dart';
import '../db/database_provider.dart';
import '../sync/sync_providers.dart';
import 'trip_offline_pack_service.dart';

final tripOfflinePackServiceProvider = Provider<TripOfflinePackService>((ref) {
  return TripOfflinePackService(
    db: ref.watch(appDatabaseProvider),
    syncQueue: ref.watch(syncQueueProvider),
  );
});

final offlinePackLifecycleProvider = Provider<void>((ref) {
  final controller = OfflinePackLifecycleController(
    service: ref.watch(tripOfflinePackServiceProvider),
    analytics: ref.watch(analyticsProvider),
  );
  final observer =
      _OfflinePackLifecycleObserver(controller.refreshOnForeground);

  WidgetsBinding.instance.addObserver(observer);
  ref.onDispose(() => WidgetsBinding.instance.removeObserver(observer));

  unawaited(controller.refreshOnForeground());
});

class OfflinePackLifecycleController {
  const OfflinePackLifecycleController({
    required TripOfflinePackService service,
    Analytics? analytics,
  })  : _service = service,
        _analytics = analytics;

  final TripOfflinePackService _service;
  final Analytics? _analytics;

  Future<void> refreshOnForeground() async {
    await _refresh(OfflinePackRefreshTrigger.appForeground);
    await _refresh(OfflinePackRefreshTrigger.preDeparture);
  }

  Future<void> _refresh(OfflinePackRefreshTrigger trigger) async {
    try {
      await _service.refreshDueLocalEssentials(trigger: trigger);
    } catch (error, stackTrace) {
      reportAndLog(
        error,
        stackTrace,
        screen: 'offline_pack',
        action: 'foreground_refresh',
        severity: ActionFailureSeverity.degraded,
        analytics: _analytics,
      );
    }
  }
}

class _OfflinePackLifecycleObserver extends WidgetsBindingObserver {
  _OfflinePackLifecycleObserver(this._onForeground);

  final Future<void> Function() _onForeground;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_onForeground());
    }
  }
}
