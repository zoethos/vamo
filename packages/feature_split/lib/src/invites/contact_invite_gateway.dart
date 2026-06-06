import 'contact_invite_target.dart';

/// Permissionless OS contact pick + SMS/email compose (S26).
abstract class ContactInviteGateway {
  bool get isSupported;

  Future<ContactInviteTarget?> pickPhoneTarget();

  Future<ContactInviteTarget?> pickEmailTarget();

  Future<bool> composeSms({required String phone, required String body});

  Future<bool> composeEmail({
    required String email,
    required String subject,
    required String body,
  });
}

/// Unsupported platforms (web, iOS until picker is ready).
class UnsupportedContactInviteGateway implements ContactInviteGateway {
  const UnsupportedContactInviteGateway();

  @override
  bool get isSupported => false;

  @override
  Future<bool> composeEmail({
    required String email,
    required String subject,
    required String body,
  }) async =>
      false;

  @override
  Future<bool> composeSms({required String phone, required String body}) async =>
      false;

  @override
  Future<ContactInviteTarget?> pickEmailTarget() async => null;

  @override
  Future<ContactInviteTarget?> pickPhoneTarget() async => null;
}
