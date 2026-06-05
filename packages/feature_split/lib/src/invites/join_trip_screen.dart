import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../trips/trips_providers.dart';
import 'invite_channel.dart';
import 'invite_labels.dart';
import 'invite_qr_scanner.dart';
import 'invites_repository.dart';
import 'pending_invite.dart';

/// Handles `/join?token=…` — joins via RPC when signed in, otherwise stores token.
class JoinTripScreen extends ConsumerStatefulWidget {
  const JoinTripScreen({
    super.key,
    required this.token,
    this.labels,
  });

  final String token;
  final InviteLabels? labels;

  @override
  ConsumerState<JoinTripScreen> createState() => _JoinTripScreenState();
}

class _JoinTripScreenState extends ConsumerState<JoinTripScreen> {
  String? _error;
  bool _joining = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    if (widget.token.isEmpty) {
      setState(() => _error = 'Invalid invite link');
      return;
    }

    if (!ref.read(isSignedInProvider)) {
      ref.read(pendingInviteTokenProvider.notifier).state = widget.token;
      ref.read(pendingInviteChannelProvider.notifier).state = InviteChannel.link;
      return;
    }

    await _join();
  }

  Future<void> _join() async {
    setState(() {
      _joining = true;
      _error = null;
    });
    try {
      final channel =
          ref.read(pendingInviteChannelProvider) ?? InviteChannel.link;
      final tripId = await ref
          .read(invitesRepositoryProvider)
          .joinTrip(widget.token, channel: channel);
      ref.read(pendingInviteTokenProvider.notifier).state = null;
      ref.read(pendingInviteChannelProvider.notifier).state = null;
      ref.invalidate(tripsSyncProvider);
      await ref.read(syncCoordinatorProvider).syncNow();
      if (!mounted) return;
      context.go(AppRoutes.trip(tripId));
    } catch (e) {
      if (!mounted) return;
      ref.read(analyticsProvider).reportActionFailed(
            screen: 'join',
            action: 'join_trip',
            error: e,
          );
      setState(() {
        _error = formatActionFailureMessage(e);
        _joining = false;
      });
    }
  }

  void _scanQr() {
    final labels = widget.labels;
    if (labels == null || !isInviteQrScanSupported) return;
    showInviteQrScannerSheet(
      context: context,
      ref: ref,
      labels: labels,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labels = widget.labels;
    final canScan = labels != null && isInviteQrScanSupported;

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_joining) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 20),
                Text(
                  'Joining trip…',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: AppColors.ink),
                ),
              ] else if (_error != null) ...[
                const Icon(Icons.error_outline,
                    size: 48, color: AppColors.sunsetCoral),
                const SizedBox(height: 16),
                Text(
                  'Could not join',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(color: AppColors.ink),
                ),
                const SizedBox(height: 8),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: AppColors.graphite),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => context.go(AppRoutes.trips),
                  child: const Text('Back to trips'),
                ),
              ] else
                const CircularProgressIndicator(),
              if (canScan) ...[
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: _scanQr,
                  icon: const Icon(Icons.qr_code_scanner_outlined),
                  label: Text(labels.scanQr),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
