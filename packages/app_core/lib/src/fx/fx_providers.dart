import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'fx_rates_client.dart';

final fxRatesClientProvider = Provider<FxRatesClient>((ref) {
  final client = FxRatesClient();
  ref.onDispose(client.clearCache);
  return client;
});
