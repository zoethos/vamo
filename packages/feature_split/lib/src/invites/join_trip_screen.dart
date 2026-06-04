import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../trips/trips_providers.dart';
import 'invites_repository.dart';
import 'pending_invite.dart';

/// Handles `/join?token=…` — joins via RPC when signed in, otherwise stores token.
class JoinTripScreen extends ConsumerStatefulWidget {
  const JoinTripScreen({super.key, required this.token});

  final String token;

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
      final tripId =
          await ref.read(invitesRepositoryProvider).joinTrip(widget.token);
      ref.read(pendingInviteTokenProvider.notifier).state = null;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                      ?.copyWith(color: AppColors.tealDark),
                ),
              ] else if (_error != null) ...[
                const Icon(Icons.error_outline,
                    size: 48, color: AppColors.sunset),
                const SizedBox(height: 16),
                Text(
                  'Could not join',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(color: AppColors.tealDark),
                ),
                const SizedBox(height: 8),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: AppColors.muted),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => context.go(AppRoutes.trips),
                  child: const Text('Back to trips'),
                ),
              ] else
                const CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}
