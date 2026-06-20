import 'package:app_core/app_core.dart';
import 'package:feature_split/feature_split.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const packageInfoChannel = MethodChannel(
    'dev.fluttercommunity.plus/package_info',
  );
  void Function(FlutterErrorDetails details)? previousErrorHandler;

  setUp(() {
    previousErrorHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exception is NetworkImageLoadException) return;
      previousErrorHandler?.call(details);
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(packageInfoChannel, (_) async {
      return {
        'appName': 'Vamo',
        'packageName': 'app.vamo',
        'version': '0.2.0',
        'buildNumber': '1',
        'buildSignature': '',
      };
    });
  });

  tearDown(() {
    FlutterError.onError = previousErrorHandler ?? FlutterError.presentError;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(packageInfoChannel, null);
  });

  testWidgets('completion screen shows avatar options when OAuth preview exists', (
    tester,
  ) async {
    final repository = _FakeProfileRepository(
      UserProfile(
        id: 'user-1',
        displayName: kPlaceholderDisplayName,
        baseCurrency: 'EUR',
      ),
      oauthPreviewUrl: 'https://provider.example/photo.jpg',
    );

    await _pumpCompletionScreen(tester, repository);

    expect(find.text('Use this'), findsOneWidget);
    expect(find.text('Upload'), findsOneWidget);
    expect(find.text('Use initials'), findsOneWidget);
  });

  testWidgets('use initials clears stored avatar path', (tester) async {
    final repository = _FakeProfileRepository(
      UserProfile(
        id: 'user-1',
        displayName: 'Maya Chen',
        baseCurrency: 'EUR',
        avatarUrl: 'user-1/profile.jpg',
      ),
    );

    await _pumpCompletionScreen(tester, repository);
    await tester.tap(find.text('Use initials'));
    await tester.pumpAndSettle();

    expect(repository.clearAvatarCalls, 1);
    expect(repository.profile.avatarUrl, isNull);
  });

  testWidgets('steady-state profile exposes avatar options to an existing user',
      (tester) async {
    final repository = _FakeProfileRepository(
      UserProfile(
        id: 'user-1',
        displayName: 'Maya Chen',
        baseCurrency: 'EUR',
      ),
      oauthPreviewUrl: 'https://provider.example/photo.jpg',
    );

    await _pumpSteadyStateProfile(tester, repository);

    expect(find.text('Profile picture'), findsOneWidget);
    expect(find.text('Upload'), findsOneWidget);
    expect(find.text('Use initials'), findsOneWidget);
  });
}

Future<void> _pumpCompletionScreen(
  WidgetTester tester,
  _FakeProfileRepository repository,
) async {
  final router = GoRouter(
    initialLocation: AppRoutes.profileCompletion,
    routes: [
      GoRoute(
        path: AppRoutes.profileCompletion,
        builder: (context, state) =>
            ProfileScreen(labels: _labels, completionRequired: true),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        profileRepositoryProvider.overrideWithValue(repository),
        userProfileProvider.overrideWith((ref) => repository.fetchCurrent()),
      ],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpSteadyStateProfile(
  WidgetTester tester,
  _FakeProfileRepository repository,
) async {
  final router = GoRouter(
    initialLocation: AppRoutes.profile,
    routes: [
      GoRoute(
        path: AppRoutes.profile,
        builder: (context, state) =>
            ProfileScreen(labels: _labels, completionRequired: false),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        profileRepositoryProvider.overrideWithValue(repository),
        userProfileProvider.overrideWith((ref) => repository.fetchCurrent()),
      ],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeProfileRepository extends ProfileRepository {
  _FakeProfileRepository(
    this.profile, {
    this.oauthPreviewUrl,
  }) : super(
          SupabaseClient(
            'http://localhost',
            'test-anon-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
        );

  UserProfile profile;
  final String? oauthPreviewUrl;
  int clearAvatarCalls = 0;

  @override
  Future<UserProfile> fetchCurrent() async => profile;

  @override
  String? oauthAvatarPreviewUrl() => oauthPreviewUrl;

  @override
  Future<String?> signedAvatarUrl(String? storagePath) async => null;

  @override
  Future<UserProfile> clearAvatar() async {
    clearAvatarCalls++;
    profile = UserProfile(
      id: profile.id,
      displayName: profile.displayName,
      baseCurrency: profile.baseCurrency,
      displayNameSetAt: profile.displayNameSetAt,
      avatarUrl: null,
    );
    return profile;
  }
}

final _labels = ProfileScreenLabels(
  title: 'Profile',
  aboutSection: 'About',
  versionLabel: 'Version',
  licenses: 'Licenses',
  privacyPolicy: 'Privacy policy',
  tagline: 'Si va?',
  loadError: 'Could not load your profile.',
  profileSection: 'Profile',
  appearanceSection: 'Appearance',
  appearanceLight: 'Light',
  appearanceDark: 'Dark',
  appearanceSystem: 'System',
  privacySection: 'Privacy',
  tagCaptureLocation: 'Tag captures with location',
  tagCaptureLocationHelper: 'Adds place + time to photos for the trip map.',
  displayName: 'Display name',
  displayNameHint: 'How Vamigos see you',
  displayNameRequired: 'Add your display name.',
  displayNameReserved: 'Choose a display name other than Vamigo.',
  pendingMediaTitle: 'Uploads in progress',
  pendingMediaBody: (count) => '$count uploads still pending',
  pendingMediaStay: 'Stay',
  pendingMediaDiscard: 'Discard anyway',
  defaultCurrency: 'Default trip currency',
  defaultCurrencyHelper: 'Used when you create a new trip',
  completionTitle: 'Finish your profile',
  completionSubtitle:
      'Add the name other trip members will see on expenses, balances, and notifications.',
  avatarSection: 'Profile picture',
  avatarUseOAuth: 'Use this',
  avatarUpload: 'Upload',
  avatarUseInitials: 'Use initials',
  billingSection: 'Billing',
  plusTitle: 'Vamo Plus',
  plusSubtitle: 'Coming soon.',
  plusSheetDescription: 'Coming soon.',
  suggestTitle: 'Suggest a feature',
  suggestSubtitle: 'We read every submission',
  devLocaleSection: 'Developer locale',
  devLocaleSystem: 'System',
  devLocaleRtl: 'RTL',
  devLocalePseudo: 'Pseudo',
  analyticsSection: 'Analytics',
  analyticsHint: 'Debug analytics.',
  posthogActive: 'PostHog is active.',
  signOut: 'Sign out',
  saveChanges: 'Save changes',
  profileSaved: 'Profile saved.',
);
