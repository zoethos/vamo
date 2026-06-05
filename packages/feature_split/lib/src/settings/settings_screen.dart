import 'package:app_core/app_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../signals/coming_soon_sheet.dart';
import '../trips/trips_repository.dart';

/// Slice 10 — profile, default currency, billing placeholder, sign-out.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _nameController = TextEditingController();
  String? _baseCurrency;
  bool _dirty = false;
  bool _saving = false;
  bool _hydrated = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AppErrorState(
          screen: 'settings',
          message: 'Could not load your profile.',
          onRetry: () => ref.invalidate(userProfileProvider),
        ),
        data: (p) {
          if (!_hydrated) {
            _hydrated = true;
            _nameController.text = p.displayName;
            _baseCurrency = p.baseCurrency;
          }
          final currency = _baseCurrency ?? p.baseCurrency;

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Profile',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Display name',
                  hintText: 'How Vamigos see you',
                ),
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() => _dirty = true),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: currency,
                decoration: const InputDecoration(
                  labelText: 'Default trip currency',
                  helperText: 'Used when you create a new trip',
                ),
                items: [
                  for (final c in kProfileCurrencies)
                    DropdownMenuItem(value: c, child: Text(c)),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    _baseCurrency = v;
                    _dirty = true;
                  });
                },
              ),
              const SizedBox(height: 32),
              Text(
                'Billing',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.workspace_premium_outlined,
                      color: AppColors.jadeTeal),
                  title: const Text('Vamo Plus'),
                  subtitle: Text(
                    'Coming soon. Tap to register interest.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.graphite),
                  ),
                  trailing: Icon(
                    Directionality.of(context) == TextDirection.rtl
                        ? Icons.chevron_left
                        : Icons.chevron_right,
                  ),
                  onTap: () => showComingSoonSheet(
                    context: context,
                    ref: ref,
                    interestEvent: VamoEvent.plusInterestTapped,
                    feature: 'plus',
                    title: 'Vamo Plus',
                    description:
                        'Upgrade anytime; downgrade or cancel at the end of '
                        'your billing cycle — no dark patterns.',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.lightbulb_outline,
                      color: AppColors.jadeTeal),
                  title: const Text('Suggest a feature'),
                  subtitle: const Text('We read every submission'),
                  trailing: Icon(
                    Directionality.of(context) == TextDirection.rtl
                        ? Icons.chevron_left
                        : Icons.chevron_right,
                  ),
                  onTap: () => context.push(AppRoutes.suggestFeature),
                ),
              ),
              const SizedBox(height: 32),
              if (kDebugMode) ...[
                Text(
                  DevLocaleLabels.section,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                SegmentedButton<DevLocaleOverride>(
                  segments: const [
                    ButtonSegment(
                      value: DevLocaleOverride.system,
                      label: Text('System'),
                    ),
                    ButtonSegment(
                      value: DevLocaleOverride.rtlArabic,
                      label: Text('RTL'),
                    ),
                    ButtonSegment(
                      value: DevLocaleOverride.pseudoLocale,
                      label: Text('Pseudo'),
                    ),
                  ],
                  selected: {ref.watch(devLocaleOverrideProvider)},
                  onSelectionChanged: (selection) {
                    ref.read(devLocaleOverrideProvider.notifier).state =
                        selection.first;
                  },
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${DevLocaleLabels.system} · ${DevLocaleLabels.rtl} · '
                    '${DevLocaleLabels.pseudo}',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.graphite),
                  ),
                ),
                const SizedBox(height: 32),
              ],
              Text(
                'Analytics',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                Env.posthogApiKey.isEmpty
                    ? 'PostHog key not set — events log to the debug console.'
                    : 'PostHog is active. Verify all ${VamoEvent.northStar.length} '
                        'North-Star events in Live events after each flow.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.graphite),
              ),
              const SizedBox(height: 8),
              ...VamoEvent.northStar.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '• ${e.name}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: _saving || !_dirty ? null : () => _save(p),
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save changes'),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: _signOut,
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _save(UserProfile previous) async {
    setState(() => _saving = true);
    try {
      await ref.read(profileRepositoryProvider).update(
            displayName: _nameController.text,
            baseCurrency: _baseCurrency ?? previous.baseCurrency,
          );
      ref.invalidate(userProfileProvider);
      if (!mounted) return;
      setState(() {
        _dirty = false;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile saved.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showActionError(
        context,
        ref,
        screen: 'settings',
        action: 'save_profile',
        error: e,
      );
    }
  }

  Future<void> _signOut() async {
    await ref.read(tripsRepositoryProvider).clearLocal();
    await ref.read(authRepositoryProvider).signOut();
  }
}
