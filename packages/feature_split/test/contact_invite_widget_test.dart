import 'package:app_core/app_core.dart';
import 'package:feature_split/src/expenses/expense_models.dart';
import 'package:feature_split/src/expenses/expenses_providers.dart';
import 'package:feature_split/src/invites/contact_invite_flow.dart';
import 'package:feature_split/src/invites/contact_invite_gateway.dart';
import 'package:feature_split/src/invites/contact_invite_target.dart';
import 'package:feature_split/src/invites/invites_repository.dart';
import 'package:feature_split/src/trips/members_tab.dart';
import 'package:feature_split/src/trips/trips_models.dart';
import 'package:feature_split/src/trips/trips_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotrue/gotrue.dart';
import 'package:supabase/supabase.dart' hide User;

import 'invite_labels_test_support.dart';

class _FakeContactInviteGateway implements ContactInviteGateway {
  _FakeContactInviteGateway({required this.isSupported});

  @override
  final bool isSupported;

  ContactInviteTarget? nextPhone;
  ContactInviteTarget? nextEmail;
  String? lastSmsPhone;
  String? lastSmsBody;
  String? lastEmail;
  String? lastEmailBody;
  bool composeSmsResult = true;
  bool composeEmailResult = true;
  Object? composeSmsError;
  Object? composeEmailError;
  Object? pickPhoneError;
  Object? pickEmailError;
  int pickPhoneCalls = 0;
  int pickEmailCalls = 0;

  @override
  Future<bool> composeEmail({
    required String email,
    required String subject,
    required String body,
  }) async {
    final error = composeEmailError;
    if (error != null) throw error;
    lastEmail = email;
    lastEmailBody = body;
    return composeEmailResult;
  }

  @override
  Future<bool> composeSms({required String phone, required String body}) async {
    final error = composeSmsError;
    if (error != null) throw error;
    lastSmsPhone = phone;
    lastSmsBody = body;
    return composeSmsResult;
  }

  @override
  Future<ContactInviteTarget?> pickEmailTarget() async {
    pickEmailCalls++;
    final error = pickEmailError;
    if (error != null) throw error;
    return nextEmail;
  }

  @override
  Future<ContactInviteTarget?> pickPhoneTarget() async {
    pickPhoneCalls++;
    final error = pickPhoneError;
    if (error != null) throw error;
    return nextPhone;
  }
}

class _FakeInvitesRepository extends InvitesRepository {
  _FakeInvitesRepository(Analytics analytics)
      : super(
          client: SupabaseClient(
            'http://localhost',
            'test-anon-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
          analytics: analytics,
        );

  @override
  Future<String> getOrCreateInviteToken(String tripId) async => 'test-token';
}

void main() {
  const tripId = 'trip-contact-invite';
  const ownerId = 'owner';

  final detail = TripDetail(
    id: tripId,
    name: 'Test trip',
    baseCurrency: 'EUR',
    ownerId: ownerId,
    lifecycle: 'active',
  );

  Widget buildMembersTab({
    required ContactInviteGateway gateway,
    ContactInviteShare? shareInvite,
  }) {
    return ProviderScope(
      overrides: [
        analyticsProvider.overrideWithValue(DebugAnalytics()),
        invitesRepositoryProvider.overrideWith(
          (ref) => _FakeInvitesRepository(ref.read(analyticsProvider)),
        ),
        tripMembersForExpenseProvider(tripId).overrideWith(
          (ref) => Stream.value([
            TripMemberView(
              userId: ownerId,
              displayName: 'Owner',
              role: 'owner',
            ),
          ]),
        ),
        tripDetailProvider(tripId).overrideWith((ref) => Stream.value(detail)),
        currentUserProvider.overrideWith(
          (ref) => User(
            id: ownerId,
            appMetadata: const {},
            userMetadata: const {},
            aud: 'authenticated',
            createdAt: DateTime.utc(2026, 1, 1).toIso8601String(),
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: MembersTab(
            tripId: tripId,
            inviteLabels: testInviteLabels,
            contactInviteGateway: gateway,
            contactInviteShare: shareInvite,
          ),
        ),
      ),
    );
  }

  testWidgets('shows contact invite action when supported', (tester) async {
    await tester.pumpWidget(
      buildMembersTab(
        gateway: _FakeContactInviteGateway(isSupported: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Invite from contacts'), findsOneWidget);
  });

  testWidgets('hides contact invite action when unsupported', (tester) async {
    await tester.pumpWidget(
      buildMembersTab(
        gateway: _FakeContactInviteGateway(isSupported: false),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Invite from contacts'), findsNothing);
  });

  testWidgets('method sheet lists text, email, and share link', (tester) async {
    await tester.pumpWidget(
      buildMembersTab(
        gateway: _FakeContactInviteGateway(isSupported: true),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Invite from contacts'));
    await tester.pumpAndSettle();

    expect(find.text('Text message'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Share link'), findsOneWidget);
  });

  testWidgets('phone path opens SMS compose with ch=contact URL',
      (tester) async {
    final gateway = _FakeContactInviteGateway(isSupported: true)
      ..nextPhone = const ContactInviteTarget(
        targetType: ContactInviteTargetType.phone,
        value: '+15550100',
      );

    await tester.pumpWidget(buildMembersTab(gateway: gateway));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Invite from contacts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Text message'));
    await tester.pumpAndSettle();

    expect(gateway.pickPhoneCalls, 1);
    expect(gateway.lastSmsPhone, '+15550100');
    expect(gateway.lastSmsBody, contains('ch=contact'));
  });

  testWidgets('email path opens email compose with ch=contact URL',
      (tester) async {
    final gateway = _FakeContactInviteGateway(isSupported: true)
      ..nextEmail = const ContactInviteTarget(
        targetType: ContactInviteTargetType.email,
        value: 'friend@example.com',
      );

    await tester.pumpWidget(buildMembersTab(gateway: gateway));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Invite from contacts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Email'));
    await tester.pumpAndSettle();

    expect(gateway.pickEmailCalls, 1);
    expect(gateway.lastEmail, 'friend@example.com');
    expect(gateway.lastEmailBody, contains('ch=contact'));
  });

  testWidgets('cancelled phone pick exits without compose', (tester) async {
    final gateway = _FakeContactInviteGateway(isSupported: true);

    await tester.pumpWidget(buildMembersTab(gateway: gateway));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Invite from contacts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Text message'));
    await tester.pumpAndSettle();

    expect(gateway.pickPhoneCalls, 1);
    expect(gateway.lastSmsPhone, isNull);
  });

  testWidgets('phone picker failure falls back to share link', (tester) async {
    final gateway = _FakeContactInviteGateway(isSupported: true)
      ..pickPhoneError = StateError('picker failed');
    var shareCalls = 0;
    String? sharedBody;

    await tester.pumpWidget(
      buildMembersTab(
        gateway: gateway,
        shareInvite: ({required body, required subject}) async {
          shareCalls++;
          sharedBody = body;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Invite from contacts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Text message'));
    await tester.pumpAndSettle();

    expect(gateway.pickPhoneCalls, 1);
    expect(gateway.lastSmsPhone, isNull);
    expect(shareCalls, 1);
    expect(sharedBody, contains('ch=contact'));
  });

  testWidgets('SMS compose failure falls back to share link', (tester) async {
    final gateway = _FakeContactInviteGateway(isSupported: true)
      ..nextPhone = const ContactInviteTarget(
        targetType: ContactInviteTargetType.phone,
        value: '+15550100',
      )
      ..composeSmsError = StateError('sms unavailable');
    var shareCalls = 0;
    String? sharedBody;

    await tester.pumpWidget(
      buildMembersTab(
        gateway: gateway,
        shareInvite: ({required body, required subject}) async {
          shareCalls++;
          sharedBody = body;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Invite from contacts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Text message'));
    await tester.pumpAndSettle();

    expect(gateway.pickPhoneCalls, 1);
    expect(gateway.lastSmsPhone, isNull);
    expect(shareCalls, 1);
    expect(sharedBody, contains('ch=contact'));
  });
}
