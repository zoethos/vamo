import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import 'contact_invite_gateway.dart';
import 'contact_invite_picker.dart';
import 'contact_invite_target.dart';
import 'invite_analytics.dart';
import 'invite_channel.dart';
import 'invite_labels.dart';
import 'invites_repository.dart';

final contactInviteGatewayProvider = Provider<ContactInviteGateway>(
  (ref) => createContactInviteGateway(),
);

typedef ContactInviteShare = Future<void> Function({
  required String body,
  required String subject,
});

enum ContactInviteMethod { textMessage, email, shareLink }

/// S26 — permissionless contact invite via OS picker + SMS/email compose.
Future<void> runContactInviteFlow({
  required BuildContext context,
  required WidgetRef ref,
  required String tripId,
  required InviteLabels labels,
  required ContactInviteGateway gateway,
  ContactInviteShare? shareInvite,
  ContactInviteMethod? initialMethod,
}) async {
  if (!gateway.isSupported && initialMethod != ContactInviteMethod.shareLink) {
    return;
  }

  final flow = FlowTracker(
    flow: 'invite',
    analytics: ref.read(analyticsProvider),
  );

  try {
    final token = await ref
        .read(invitesRepositoryProvider)
        .getOrCreateInviteToken(tripId);
    if (!context.mounted) {
      flow.abandonIfIncomplete();
      return;
    }

    final web = InviteUrls.webInviteLink(
      token,
      channel: InviteChannel.contact.analyticsValue,
    );
    final app = InviteUrls.appInviteUri(
      token,
      channel: InviteChannel.contact.analyticsValue,
    );
    final body = labels.contactInviteBody(web, app.toString());
    final subject = labels.contactInviteSubject;

    final method = initialMethod ?? await _showMethodSheet(context, labels);
    if (method == null || !context.mounted) {
      flow.abandonIfIncomplete();
      return;
    }

    switch (method) {
      case ContactInviteMethod.textMessage:
        final target = await _pickSafely(gateway.pickPhoneTarget);
        if (target == null || !context.mounted) {
          flow.abandonIfIncomplete();
          return;
        }
        if (target.targetType == ContactInviteTargetType.shareFallback) {
          await _shareFallback(
            context: context,
            ref: ref,
            tripId: tripId,
            labels: labels,
            body: body,
            subject: subject,
            flow: flow,
            shareInvite: shareInvite,
          );
          return;
        }
        final composed = await _composeSafely(
          () => gateway.composeSms(
            phone: target.value,
            body: body,
          ),
        );
        if (composed) {
          captureMemberInvitedShow(
            ref.read(analyticsProvider),
            tripId: tripId,
            channel: InviteChannel.contact,
            targetType: ContactInviteTargetType.phone,
          );
          flow.complete();
          return;
        }
        if (!context.mounted) {
          flow.abandonIfIncomplete();
          return;
        }
        await _shareFallback(
          context: context,
          ref: ref,
          tripId: tripId,
          labels: labels,
          body: body,
          subject: subject,
          flow: flow,
          shareInvite: shareInvite,
        );
      case ContactInviteMethod.email:
        final target = await _pickSafely(gateway.pickEmailTarget);
        if (target == null || !context.mounted) {
          flow.abandonIfIncomplete();
          return;
        }
        if (target.targetType == ContactInviteTargetType.shareFallback) {
          await _shareFallback(
            context: context,
            ref: ref,
            tripId: tripId,
            labels: labels,
            body: body,
            subject: subject,
            flow: flow,
            shareInvite: shareInvite,
          );
          return;
        }
        final composed = await _composeSafely(
          () => gateway.composeEmail(
            email: target.value,
            subject: subject,
            body: body,
          ),
        );
        if (composed) {
          captureMemberInvitedShow(
            ref.read(analyticsProvider),
            tripId: tripId,
            channel: InviteChannel.contact,
            targetType: ContactInviteTargetType.email,
          );
          flow.complete();
          return;
        }
        if (!context.mounted) {
          flow.abandonIfIncomplete();
          return;
        }
        await _shareFallback(
          context: context,
          ref: ref,
          tripId: tripId,
          labels: labels,
          body: body,
          subject: subject,
          flow: flow,
          shareInvite: shareInvite,
        );
      case ContactInviteMethod.shareLink:
        await _shareFallback(
          context: context,
          ref: ref,
          tripId: tripId,
          labels: labels,
          body: body,
          subject: subject,
          flow: flow,
          shareInvite: shareInvite,
        );
    }
  } catch (e) {
    flow.abandonIfIncomplete();
    if (!context.mounted) return;
    showActionError(
      context,
      ref,
      screen: 'trip_home',
      action: 'contact_invite',
      error: e,
    );
  }
}

Future<ContactInviteTarget?> _pickSafely(
  Future<ContactInviteTarget?> Function() pick,
) async {
  try {
    return await pick();
  } catch (_) {
    return const ContactInviteTarget(
      targetType: ContactInviteTargetType.shareFallback,
      value: '',
    );
  }
}

Future<bool> _composeSafely(Future<bool> Function() compose) async {
  try {
    return await compose();
  } catch (_) {
    return false;
  }
}

Future<ContactInviteMethod?> _showMethodSheet(
  BuildContext context,
  InviteLabels labels,
) {
  return showModalBottomSheet<ContactInviteMethod>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.sms_outlined),
            title: Text(labels.contactMethodTextMessage),
            onTap: () => Navigator.pop(ctx, ContactInviteMethod.textMessage),
          ),
          ListTile(
            leading: const Icon(Icons.email_outlined),
            title: Text(labels.contactMethodEmail),
            onTap: () => Navigator.pop(ctx, ContactInviteMethod.email),
          ),
          ListTile(
            leading: const Icon(Icons.share_outlined),
            title: Text(labels.contactMethodShareLink),
            onTap: () => Navigator.pop(ctx, ContactInviteMethod.shareLink),
          ),
        ],
      ),
    ),
  );
}

Future<void> _shareFallback({
  required BuildContext context,
  required WidgetRef ref,
  required String tripId,
  required InviteLabels labels,
  required String body,
  required String subject,
  required FlowTracker flow,
  ContactInviteShare? shareInvite,
}) async {
  final share = shareInvite;
  if (share == null) {
    await Share.share(body, subject: subject);
  } else {
    await share(body: body, subject: subject);
  }
  captureMemberInvitedShow(
    ref.read(analyticsProvider),
    tripId: tripId,
    channel: InviteChannel.contact,
    targetType: ContactInviteTargetType.shareFallback,
  );
  flow.complete();
}
