import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('GoRouterRefreshStream treats auth stream errors as refreshes',
      () async {
    final controller = StreamController<Object>();
    final refresh = GoRouterRefreshStream(controller.stream);
    var notifications = 0;
    refresh.addListener(() => notifications += 1);

    controller.addError(StateError('auth callback failed'));
    await Future<void>.delayed(Duration.zero);

    expect(notifications, 1);

    refresh.dispose();
    await controller.close();
  });
}
