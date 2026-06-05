import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'invite_labels.dart';

/// Web/desktop — scan entry hidden; links still work.
bool get isInviteQrScanSupported => false;

Future<void> showInviteQrScannerSheet({
  required BuildContext context,
  required WidgetRef ref,
  required InviteLabels labels,
}) async {}
