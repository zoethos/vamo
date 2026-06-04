import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';

class VamoApp extends ConsumerStatefulWidget {
  const VamoApp({super.key});

  @override
  ConsumerState<VamoApp> createState() => _VamoAppState();
}

class _VamoAppState extends ConsumerState<VamoApp> {
  StreamSubscription<Uri>? _linkSubscription;
  final _appLinks = AppLinks();

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initDeepLinks() async {
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) _handleDeepLink(initial);

      _linkSubscription = _appLinks.uriLinkStream.listen(_handleDeepLink);
    } catch (_) {
      // Platform may be unavailable in tests / desktop without config.
    }
  }

  void _handleDeepLink(Uri uri) {
    if (AuthUrls.isAuthCallback(uri)) {
      ref
          .read(routerProvider)
          .go(AuthUrls.inAppLoginCallbackLocation(uri));
      return;
    }

    final token = InviteUrls.parseToken(uri);
    if (token == null) return;
    ref.read(routerProvider).go(InviteUrls.inAppJoinLocation(token));
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(syncLifecycleProvider);
    ref.watch(analyticsLifecycleProvider);
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Vamo',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: router,
    );
  }
}
