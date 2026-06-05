import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'invite_analytics.dart';
import 'invite_channel.dart';
import 'invite_labels.dart';

/// Full-screen sheet: app-scheme invite as QR (same token as link share).
Future<void> showInviteQrSheet({
  required BuildContext context,
  required Analytics analytics,
  required String tripId,
  required String tripName,
  required String token,
  required InviteLabels labels,
}) {
  captureMemberInvitedShow(
    analytics,
    tripId: tripId,
    channel: InviteChannel.qr,
  );

  final payload = InviteUrls.qrInvitePayload(token);

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => SizedBox(
      height: MediaQuery.sizeOf(ctx).height * 0.92,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: const BoxDecoration(gradient: AppColors.brandGradient),
            padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 20, 20),
            child: Column(
              children: [
                Image.asset(
                  BrandAssets.markWhite,
                  height: 40,
                ),
                const SizedBox(height: 12),
                Text(
                  tripName,
                  textAlign: TextAlign.center,
                  style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsetsDirectional.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.mistGray),
                      ),
                      child: Padding(
                        padding: const EdgeInsetsDirectional.all(16),
                        child: QrImageView(
                          data: payload,
                          size: 240,
                          backgroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      labels.qrCaption,
                      textAlign: TextAlign.center,
                      style: Theme.of(ctx).textTheme.bodyLarge?.copyWith(
                            color: AppColors.graphite,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
