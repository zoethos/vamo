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

  testWidgets(
      'completion screen shows avatar options when OAuth preview exists', (
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

  testWidgets('use initials preserves stored avatar path for switching back', (
    tester,
  ) async {
    final repository = _FakeProfileRepository(
      UserProfile(
        id: 'user-1',
        displayName: 'Maya Chen',
        baseCurrency: 'EUR',
        avatarUrl: 'user-1/profile.jpg',
      ),
    );

    await _pumpCompletionScreen(tester, repository);
    await tester.ensureVisible(find.text('Use initials'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use initials'));
    await tester.pumpAndSettle();

    expect(repository.useInitialsCalls, 1);
    expect(repository.profile.avatarUrl, 'user-1/profile.jpg');
    expect(repository.profile.avatarDisplayMode, AvatarDisplayMode.initials);
    expect(find.text('Use photo'), findsOneWidget);

    await tester.tap(find.text('Use photo'));
    await tester.pumpAndSettle();

    expect(repository.usePhotoCalls, 1);
    expect(repository.profile.avatarDisplayMode, AvatarDisplayMode.photo);
  });

  testWidgets('custom initials or alias are persisted for avatar fallback', (
    tester,
  ) async {
    final repository = _FakeProfileRepository(
      UserProfile(
        id: 'user-1',
        displayName: 'Maya Luna Chen',
        baseCurrency: 'EUR',
        avatarUrl: 'user-1/profile.jpg',
      ),
    );

    await _pumpCompletionScreen(tester, repository);
    await tester.enterText(_avatarInitialsField(), 'mlc');
    await tester.ensureVisible(find.text('Use initials'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use initials'));
    await tester.pumpAndSettle();

    expect(repository.profile.avatarUrl, 'user-1/profile.jpg');
    expect(repository.profile.avatarInitials, 'MLC');
    expect(repository.profile.avatarDisplayMode, AvatarDisplayMode.initials);
  });

  testWidgets('remove photo confirms and deletes stored avatar path', (
    tester,
  ) async {
    final repository = _FakeProfileRepository(
      UserProfile(
        id: 'user-1',
        displayName: 'Maya Chen',
        baseCurrency: 'EUR',
        avatarUrl: 'user-1/profile.jpg',
      ),
    );

    await _pumpCompletionScreen(tester, repository);
    await tester.tap(find.text('Remove photo'));
    await tester.pumpAndSettle();

    expect(find.text('Remove profile photo?'), findsOneWidget);

    await tester.tap(find.text('Remove photo').last);
    await tester.pumpAndSettle();

    expect(repository.clearAvatarCalls, 1);
    expect(repository.profile.avatarUrl, isNull);
    expect(repository.profile.avatarDisplayMode, AvatarDisplayMode.initials);
  });

  testWidgets(
      'steady-state profile head and settings rows open sheets on tap',
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

    expect(find.byKey(const Key('profileHeaderDisplayName')), findsOneWidget);
    expect(find.byKey(const Key('profileHeaderTagline')), findsOneWidget);
    expect(find.text('Si va?'), findsOneWidget);
    expect(find.byKey(const Key('profileSaveBar')), findsOneWidget);
    expect(find.text('Save changes'), findsOneWidget);
    expect(find.byKey(const Key('profileDisplayNameField')), findsNothing);
    expect(find.text('Profile picture'), findsNothing);

    await tester.ensureVisible(find.byKey(const Key('profileRowDisplayName')));
    await tester.tap(find.byKey(const Key('profileRowDisplayName')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profileDisplayNameField')), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('profileRowCurrency')));
    await tester.tap(find.byKey(const Key('profileRowCurrency')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profileCurrencyOption_USD')), findsOneWidget);
    await tester.tap(find.byKey(const Key('profileCurrencyOption_USD')));
    await tester.pumpAndSettle();
    expect(find.text('USD'), findsWidgets);

    await tester.ensureVisible(find.byKey(const Key('profileRowTheme')));
    await tester.tap(find.byKey(const Key('profileRowTheme')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profileThemeOption_dark')), findsOneWidget);
  });

  testWidgets('steady-state avatar sheet opens from header tap', (tester) async {
    final repository = _FakeProfileRepository(
      UserProfile(
        id: 'user-1',
        displayName: 'Maya Chen',
        baseCurrency: 'EUR',
      ),
      oauthPreviewUrl: 'https://provider.example/photo.jpg',
    );

    await _pumpSteadyStateProfile(tester, repository);

    await tester.tap(find.byKey(const Key('profileHeaderAvatar')));
    await tester.pumpAndSettle();

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
  int useInitialsCalls = 0;
  int usePhotoCalls = 0;
  int clearAvatarCalls = 0;

  @override
  Future<UserProfile> fetchCurrent() async => profile;

  @override
  String? oauthAvatarPreviewUrl() => oauthPreviewUrl;

  @override
  Future<String?> signedAvatarUrl(String? storagePath) async => null;

  @override
  Future<UserProfile> useInitialsAvatar(String? initials) async {
    useInitialsCalls++;
    profile = UserProfile(
      id: profile.id,
      displayName: profile.displayName,
      baseCurrency: profile.baseCurrency,
      displayNameSetAt: profile.displayNameSetAt,
      avatarUrl: profile.avatarUrl,
      avatarDisplayMode: AvatarDisplayMode.initials,
      avatarInitials: initials == null || initials.trim().isEmpty
          ? null
          : normalizeAvatarInitials(initials),
    );
    return profile;
  }

  @override
  Future<UserProfile> usePhotoAvatar() async {
    usePhotoCalls++;
    profile = UserProfile(
      id: profile.id,
      displayName: profile.displayName,
      baseCurrency: profile.baseCurrency,
      displayNameSetAt: profile.displayNameSetAt,
      avatarUrl: profile.avatarUrl,
      avatarDisplayMode: AvatarDisplayMode.photo,
      avatarInitials: profile.avatarInitials,
    );
    return profile;
  }

  @override
  Future<UserProfile> clearAvatar() async {
    clearAvatarCalls++;
    profile = UserProfile(
      id: profile.id,
      displayName: profile.displayName,
      baseCurrency: profile.baseCurrency,
      displayNameSetAt: profile.displayNameSetAt,
      avatarDisplayMode: AvatarDisplayMode.initials,
      avatarInitials: profile.avatarInitials,
    );
    return profile;
  }
}

Finder _avatarInitialsField() {
  return find.byKey(const Key('profileAvatarInitialsField'));
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
  avatarUsePhoto: 'Use photo',
  avatarRemovePhoto: 'Remove photo',
  avatarRemovePhotoTitle: 'Remove profile photo?',
  avatarRemovePhotoBody:
      'This deletes your uploaded photo from Vamo storage. You can keep using initials without deleting it.',
  avatarRemovePhotoCancel: 'Keep photo',
  avatarRemovePhotoConfirm: 'Remove photo',
  avatarInitialsLabel: 'Initials or alias',
  avatarInitialsHint: 'Up to 4 characters',
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
