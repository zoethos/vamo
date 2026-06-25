import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:app_links/app_links.dart';
import 'package:feature_split/feature_split.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'l10n/app_localizations.dart';
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(pushNotificationRouteHandlerProvider.notifier).state =
          _handlePushRoute;
    });
  }

  void _handlePushRoute(String route) {
    final token = inviteTokenFromLocation(route);
    if (token != null) {
      ref.read(routerProvider).go(InviteUrls.inAppJoinLocation(token));
      return;
    }
    ref.read(routerProvider).go(route);
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
    } catch (error, stackTrace) {
      // Platform may be unavailable in tests / desktop without config.
      reportAndLog(
        error,
        stackTrace,
        screen: 'app_lifecycle',
        action: 'deep_link_init',
        severity: ActionFailureSeverity.degraded,
        analytics: ref.read(analyticsProvider),
      );
    }
  }

  void _handleDeepLink(Uri uri) {
    if (AuthUrls.isAuthCallback(uri)) {
      ref.read(routerProvider).go(AuthUrls.inAppLoginCallbackLocation(uri));
      return;
    }

    final token = InviteUrls.parseToken(uri);
    if (token == null) return;
    final channel = InviteChannel.fromQuery(InviteUrls.channelQuery(uri));
    ref.read(pendingInviteChannelProvider.notifier).state = channel;
    ref.read(routerProvider).go(
          InviteUrls.inAppJoinLocation(
            token,
            channel: InviteUrls.channelQuery(uri),
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(syncLifecycleProvider);
    ref.watch(offlinePackLifecycleProvider);
    ref.watch(analyticsLifecycleProvider);
    ref.watch(pushLifecycleProvider);
    final router = ref.watch(routerProvider);
    final localeOverride = ref.watch(devLocaleOverrideProvider);
    final locale = resolveDevLocale(localeOverride);
    final themePreference = ref.watch(themePreferenceProvider);

    return MaterialApp.router(
      title: 'Vamo',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themePreference.themeMode,
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocales.supported,
      routerConfig: router,
      builder: (context, child) {
        if (!kDebugMode ||
            localeOverride != DevLocaleOverride.pseudoLocale ||
            child == null) {
          return child ?? const SizedBox.shrink();
        }
        return _PseudoLocaleWrapper(child: child);
      },
    );
  }
}

/// Elongates visible text to surface layout overflow issues (dev pseudo-locale).
class _PseudoLocaleWrapper extends StatelessWidget {
  const _PseudoLocaleWrapper({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Localizations.override(
      context: context,
      locale: AppLocales.pseudo,
      child: Builder(
        builder: (context) {
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(
              boldText: true,
            ),
            child: child,
          );
        },
      ),
    );
  }
}
