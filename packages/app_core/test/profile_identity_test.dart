import 'package:app_core/app_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('profileNeedsIdentityCompletion', () {
    test('requires completion when display name was never set', () {
      expect(
        profileNeedsIdentityCompletion(
          displayName: 'Vamigo',
          displayNameSetAt: null,
        ),
        isTrue,
      );
    });

    test('accepts a non-placeholder name with a completion timestamp', () {
      expect(
        profileNeedsIdentityCompletion(
          displayName: 'Maya Chen',
          displayNameSetAt: DateTime.utc(2026, 6, 17),
        ),
        isFalse,
      );
    });
  });

  group('fallbackMemberDisplayName', () {
    test('uses real display names', () {
      expect(
        fallbackMemberDisplayName(
          userId: '9ada6512-b35e-4c54-ba86-493cf9fcbe87',
          displayName: 'Maya',
        ),
        'Maya',
      );
    });

    test('turns placeholder names into stable short member labels', () {
      expect(
        fallbackMemberDisplayName(
          userId: '9ada6512-b35e-4c54-ba86-493cf9fcbe87',
          displayName: 'Vamigo',
        ),
        'Member be87',
      );
    });
  });
}
