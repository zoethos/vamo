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

  setUp(() {
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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(packageInfoChannel, null);
  });

  testWidgets('completion mode rejects placeholder then continues after save', (
    tester,
  ) async {
    final repository = _FakeProfileRepository(
      UserProfile(
        id: 'user-1',
        displayName: kPlaceholderDisplayName,
        baseCurrency: 'EUR',
      ),
    );

    final router = GoRouter(
      initialLocation: AppRoutes.profileCompletion,
      routes: [
        GoRoute(
          path: AppRoutes.profileCompletion,
          builder: (context, state) =>
              ProfileScreen(labels: _labels, completionRequired: true),
        ),
        GoRoute(
          path: AppRoutes.trips,
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Trips ready'))),
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

    expect(find.text('Finish your profile'), findsOneWidget);
    expect(find.text(kPlaceholderDisplayName), findsNothing);

    await tester.scrollUntilVisible(
      _displayNameField(),
      48,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      _displayNameField(),
      kPlaceholderDisplayName,
    );
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Save changes'),
      48,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(
      find.text('Choose a display name other than Vamigo.'),
      findsOneWidget,
    );

    await tester.scrollUntilVisible(
      _displayNameField(),
      48,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      _displayNameField(),
      'Maya Chen',
    );
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Save changes'),
      48,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(repository.profile.displayName, 'Maya Chen');
    expect(repository.profile.displayNameSetAt, isNotNull);
    expect(find.text('Trips ready'), findsOneWidget);
  });
}

Finder _displayNameField() {
  return find.byKey(const Key('profileDisplayNameField'));
}

class _FakeProfileRepository extends ProfileRepository {
  _FakeProfileRepository(this.profile)
      : super(
          SupabaseClient(
            'http://localhost',
            'test-anon-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
        );

  UserProfile profile;

  @override
  Future<UserProfile> fetchCurrent() async => profile;

  @override
  Future<UserProfile> update({
    required String displayName,
    required String baseCurrency,
  }) async {
    final trimmed = normalizeDisplayName(displayName);
    if (!isUsableDisplayName(trimmed)) {
      throw ArgumentError('Invalid display name');
    }
    profile = UserProfile(
      id: profile.id,
      displayName: trimmed,
      baseCurrency: baseCurrency,
      displayNameSetAt: DateTime.utc(2026, 6, 17),
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
