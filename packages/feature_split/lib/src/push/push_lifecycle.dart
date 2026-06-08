import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'push_devices_repository.dart';

/// Override in the app shell with a Firebase-backed [PushRegistrar].
final pushRegistrarProvider = Provider<PushRegistrar>((ref) {
  throw UnimplementedError(
    'pushRegistrarProvider must be overridden in the app shell',
  );
});

/// Set by [VamoApp] so push taps use the same router as deep links.
final pushNotificationRouteHandlerProvider =
    StateProvider<void Function(String route)>((ref) {
  return (_) {};
});

/// Registers FCM tokens after sign-in; routes notification taps via [onRoute].
final pushLifecycleProvider = Provider<void>((ref) {
  final registrar = ref.watch(pushRegistrarProvider);
  final devices = ref.watch(pushDevicesRepositoryProvider);
  debugBreadcrumb('mounted', screen: 'push', action: 'push_lifecycle');

  Future<void> bind(bool signedIn) async {
    if (!signedIn) {
      debugBreadcrumb('stop', screen: 'push', action: 'push_lifecycle');
      await registrar.stop();
      return;
    }
    debugBreadcrumb('start', screen: 'push', action: 'push_lifecycle');
    await registrar.start(
      onRoute: (route) => ref.read(pushNotificationRouteHandlerProvider)(route),
      onToken: (token) {
        unawaited(devices.registerToken(token));
      },
    );
  }

  ref.listen(authStateChangesProvider, (prev, next) {
    final wasSignedIn = prev?.valueOrNull?.session != null;
    final signedIn = next.valueOrNull?.session != null;
    if (signedIn != wasSignedIn) {
      unawaited(bind(signedIn));
    }
  });

  final signedIn =
      ref.watch(authStateChangesProvider).valueOrNull?.session != null;
  unawaited(bind(signedIn));

  ref.onDispose(() {
    unawaited(registrar.stop());
  });
});
