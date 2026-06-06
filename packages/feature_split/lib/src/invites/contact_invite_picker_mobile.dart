import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'contact_invite_gateway.dart';
import 'contact_invite_target.dart';

ContactInviteGateway createContactInviteGateway() {
  if (!kIsWeb && Platform.isAndroid) {
    return const AndroidContactInviteGateway();
  }
  return const UnsupportedContactInviteGateway();
}

class AndroidContactInviteGateway implements ContactInviteGateway {
  const AndroidContactInviteGateway();

  static const _channel = MethodChannel('app.vamo/contact_invite');

  @override
  bool get isSupported => true;

  @override
  Future<ContactInviteTarget?> pickPhoneTarget() async {
    final result =
        await _channel.invokeMethod<Map<Object?, Object?>>('pickPhone');
    return _parseTarget(result, ContactInviteTargetType.phone);
  }

  @override
  Future<ContactInviteTarget?> pickEmailTarget() async {
    final result =
        await _channel.invokeMethod<Map<Object?, Object?>>('pickEmail');
    return _parseTarget(result, ContactInviteTargetType.email);
  }

  @override
  Future<bool> composeSms({
    required String phone,
    required String body,
  }) async {
    final normalized = phone.trim();
    if (normalized.isEmpty) return false;
    final uri = Uri(
      scheme: 'sms',
      path: normalized,
      query: _encodeQueryParameters({'body': body}),
    );
    try {
      return await launchUrl(uri);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> composeEmail({
    required String email,
    required String subject,
    required String body,
  }) async {
    final normalized = email.trim();
    if (normalized.isEmpty) return false;
    final uri = Uri(
      scheme: 'mailto',
      path: normalized,
      query: _encodeQueryParameters({
        'subject': subject,
        'body': body,
      }),
    );
    try {
      return await launchUrl(uri);
    } catch (_) {
      return false;
    }
  }

  ContactInviteTarget? _parseTarget(
    Map<Object?, Object?>? result,
    ContactInviteTargetType type,
  ) {
    if (result == null) return null;
    final value = result['value']?.toString().trim();
    if (value == null || value.isEmpty) return null;
    final label = result['displayLabel']?.toString().trim();
    return ContactInviteTarget(
      targetType: type,
      value: value,
      displayLabel: label == null || label.isEmpty ? null : label,
    );
  }

  String _encodeQueryParameters(Map<String, String> params) {
    return params.entries
        .map(
          (entry) =>
              '${Uri.encodeComponent(entry.key)}=${Uri.encodeComponent(entry.value)}',
        )
        .join('&');
  }
}
