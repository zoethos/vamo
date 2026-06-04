import 'package:app_core/app_core.dart';
import 'package:feature_split/feature_split.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Env.load();
  await initPostHog();
  // detectSessionInUri defaults true — supabase_flutter exchanges PKCE from
  // app.vamo://login-callback; AuthCallbackScreen only waits for signedIn.
  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabaseAnonKey,
  );

  runApp(
    ProviderScope(
      overrides: [
        remoteSyncGatewayProvider.overrideWith(
          (ref) => TripsRemoteSyncGateway(ref.watch(tripsRepositoryProvider)),
        ),
      ],
      child: const VamoApp(),
    ),
  );
}
