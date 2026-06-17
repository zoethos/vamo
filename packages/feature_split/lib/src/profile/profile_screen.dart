import 'package:app_core/app_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../signals/coming_soon_sheet.dart';
import '../trips/trips_repository.dart';

class ProfileScreenLabels {
  const ProfileScreenLabels({
    required this.title,
    required this.aboutSection,
    required this.versionLabel,
    required this.licenses,
    required this.privacyPolicy,
    required this.tagline,
    required this.loadError,
    required this.profileSection,
    required this.appearanceSection,
    required this.appearanceLight,
    required this.appearanceDark,
    required this.appearanceSystem,
    required this.privacySection,
    required this.tagCaptureLocation,
    required this.tagCaptureLocationHelper,
    required this.displayName,
    required this.displayNameHint,
    required this.defaultCurrency,
    required this.defaultCurrencyHelper,
    required this.billingSection,
    required this.plusTitle,
    required this.plusSubtitle,
    required this.plusSheetDescription,
    required this.suggestTitle,
    required this.suggestSubtitle,
    required this.devLocaleSection,
    required this.devLocaleSystem,
    required this.devLocaleRtl,
    required this.devLocalePseudo,
    required this.analyticsSection,
    required this.analyticsHint,
    required this.posthogActive,
    required this.signOut,
    required this.saveChanges,
    required this.profileSaved,
  });

  final String title;
  final String aboutSection;
  final String versionLabel;
  final String licenses;
  final String privacyPolicy;
  final String tagline;
  final String loadError;
  final String profileSection;
  final String appearanceSection;
  final String appearanceLight;
  final String appearanceDark;
  final String appearanceSystem;
  final String privacySection;
  final String tagCaptureLocation;
  final String tagCaptureLocationHelper;
  final String displayName;
  final String displayNameHint;
  final String defaultCurrency;
  final String defaultCurrencyHelper;
  final String billingSection;
  final String plusTitle;
  final String plusSubtitle;
  final String plusSheetDescription;
  final String suggestTitle;
  final String suggestSubtitle;
  final String devLocaleSection;
  final String devLocaleSystem;
  final String devLocaleRtl;
  final String devLocalePseudo;
  final String analyticsSection;
  final String analyticsHint;
  final String posthogActive;
  final String signOut;
  final String saveChanges;
  final String profileSaved;
}

/// Profile tab — settings + About (version, brand, licenses, privacy).
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key, required this.labels});

  final ProfileScreenLabels labels;

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _nameController = TextEditingController();
  String? _baseCurrency;
  bool _dirty = false;
  bool _saving = false;
  bool _hydrated = false;
  String? _version;

  @override
  void initState() {
    super.initState();
    SuggestionsRepository.appVersionLabel().then((v) {
      if (mounted) setState(() => _version = v);
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider);

    return Scaffold(
      appBar: AppBar(title: Text(widget.labels.title)),
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AppErrorState(
          screen: 'profile',
          message: widget.labels.loadError,
          onRetry: () => ref.invalidate(userProfileProvider),
        ),
        data: (p) {
          if (!_hydrated) {
            _hydrated = true;
            _nameController.text = p.displayName;
            _baseCurrency = p.baseCurrency;
          }
          final currency = _baseCurrency ?? p.baseCurrency;
          final tagCaptureLocation =
              ref.watch(captureLocationTaggingProvider);

          return ListView(
            padding: const EdgeInsetsDirectional.all(20),
            children: [
              _AboutBlock(
                version: _version,
                versionLabel: widget.labels.versionLabel,
                tagline: widget.labels.tagline,
                licensesLabel: widget.labels.licenses,
                privacyLabel: widget.labels.privacyPolicy,
              ),
              const SizedBox(height: 24),
              Text(
                widget.labels.profileSection,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: widget.labels.displayName,
                  hintText: widget.labels.displayNameHint,
                ),
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() => _dirty = true),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: currency,
                decoration: InputDecoration(
                  labelText: widget.labels.defaultCurrency,
                  helperText: widget.labels.defaultCurrencyHelper,
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
              const SizedBox(height: 24),
              Text(
                widget.labels.appearanceSection,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: context.vamoColors.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              SegmentedButton<VamoThemePreference>(
                segments: [
                  ButtonSegment(
                    value: VamoThemePreference.light,
                    label: Text(widget.labels.appearanceLight),
                  ),
                  ButtonSegment(
                    value: VamoThemePreference.dark,
                    label: Text(widget.labels.appearanceDark),
                  ),
                  ButtonSegment(
                    value: VamoThemePreference.system,
                    label: Text(widget.labels.appearanceSystem),
                  ),
                ],
                selected: {ref.watch(themePreferenceProvider)},
                onSelectionChanged: (selection) {
                  ref
                      .read(themePreferenceProvider.notifier)
                      .setPreference(selection.first);
                },
              ),
              const SizedBox(height: 24),
              Text(
                widget.labels.privacySection,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: context.vamoColors.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(widget.labels.tagCaptureLocation),
                subtitle: Text(
                  widget.labels.tagCaptureLocationHelper,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.graphite),
                ),
                value: tagCaptureLocation,
                onChanged: (enabled) {
                  ref
                      .read(captureLocationTaggingProvider.notifier)
                      .setEnabled(enabled);
                },
              ),
              const SizedBox(height: 24),
              Text(
                widget.labels.billingSection,
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
                  title: Text(widget.labels.plusTitle),
                  subtitle: Text(
                    widget.labels.plusSubtitle,
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
                    title: widget.labels.plusTitle,
                    description: widget.labels.plusSheetDescription,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.lightbulb_outline,
                      color: AppColors.jadeTeal),
                  title: Text(widget.labels.suggestTitle),
                  subtitle: Text(widget.labels.suggestSubtitle),
                  trailing: Icon(
                    Directionality.of(context) == TextDirection.rtl
                        ? Icons.chevron_left
                        : Icons.chevron_right,
                  ),
                  onTap: () => context.push(AppRoutes.suggestFeature),
                ),
              ),
              if (kDebugMode) ...[
                const SizedBox(height: 24),
                Text(
                  widget.labels.devLocaleSection,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                SegmentedButton<DevLocaleOverride>(
                  segments: [
                    ButtonSegment(
                      value: DevLocaleOverride.system,
                      label: Text(widget.labels.devLocaleSystem),
                    ),
                    ButtonSegment(
                      value: DevLocaleOverride.rtlArabic,
                      label: Text(widget.labels.devLocaleRtl),
                    ),
                    ButtonSegment(
                      value: DevLocaleOverride.pseudoLocale,
                      label: Text(widget.labels.devLocalePseudo),
                    ),
                  ],
                  selected: {ref.watch(devLocaleOverrideProvider)},
                  onSelectionChanged: (selection) {
                    ref.read(devLocaleOverrideProvider.notifier).state =
                        selection.first;
                  },
                ),
              ],
              const SizedBox(height: 24),
              Text(
                widget.labels.analyticsSection,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                Env.posthogApiKey.isEmpty
                    ? widget.labels.analyticsHint
                    : widget.labels.posthogActive,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.graphite),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving || !_dirty ? null : () => _save(p),
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(widget.labels.saveChanges),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _signOut,
                icon: const Icon(Icons.logout),
                label: Text(widget.labels.signOut),
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
        SnackBar(content: Text(widget.labels.profileSaved)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showActionError(
        context,
        ref,
        screen: 'profile',
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

class _AboutBlock extends StatelessWidget {
  const _AboutBlock({
    required this.version,
    required this.versionLabel,
    required this.tagline,
    required this.licensesLabel,
    required this.privacyLabel,
  });

  final String? version;
  final String versionLabel;
  final String tagline;
  final String licensesLabel;
  final String privacyLabel;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(20),
        child: Column(
          children: [
            Image.asset(
              BrandAssets.primaryMark,
              height: 56,
            ),
            const SizedBox(height: 8),
            Text(
              tagline,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            if (version != null) ...[
              const SizedBox(height: 8),
              Text(
                '$versionLabel $version',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.graphite,
                    ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () => showLicensePage(
                    context: context,
                    applicationName: 'Vamo',
                    applicationVersion: version ?? '',
                  ),
                  child: Text(licensesLabel),
                ),
                TextButton(
                  onPressed: () async {
                    final uri = Uri.parse('https://vamo.world/privacy');
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
                  child: Text(privacyLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
