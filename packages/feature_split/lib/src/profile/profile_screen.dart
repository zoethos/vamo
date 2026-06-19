import 'package:app_core/app_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
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
    required this.displayNameRequired,
    required this.displayNameReserved,
    required this.defaultCurrency,
    required this.defaultCurrencyHelper,
    required this.completionTitle,
    required this.completionSubtitle,
    required this.avatarSection,
    required this.avatarUseOAuth,
    required this.avatarUpload,
    required this.avatarUseInitials,
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
    required this.pendingMediaTitle,
    required this.pendingMediaBody,
    required this.pendingMediaStay,
    required this.pendingMediaDiscard,
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
  final String displayNameRequired;
  final String displayNameReserved;
  final String defaultCurrency;
  final String defaultCurrencyHelper;
  final String completionTitle;
  final String completionSubtitle;
  final String avatarSection;
  final String avatarUseOAuth;
  final String avatarUpload;
  final String avatarUseInitials;
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
  final String pendingMediaTitle;
  final String Function(int count) pendingMediaBody;
  final String pendingMediaStay;
  final String pendingMediaDiscard;
}

/// Profile tab — settings + About (version, brand, licenses, privacy).
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({
    super.key,
    required this.labels,
    this.completionRequired = false,
  });

  final ProfileScreenLabels labels;
  final bool completionRequired;

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _nameController = TextEditingController();
  String? _baseCurrency;
  bool _dirty = false;
  bool _saving = false;
  bool _signingOut = false;
  bool _hydrated = false;
  String? _version;
  String? _nameError;
  String? _avatarPhotoUrl;
  bool _avatarBusy = false;
  bool _avatarPreviewLoaded = false;

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
      appBar: AppBar(
        title: Text(
          widget.completionRequired
              ? widget.labels.completionTitle
              : widget.labels.title,
        ),
      ),
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AppErrorState(
          screen: 'profile',
          message: widget.labels.loadError,
          onRetry: () => ref.invalidate(userProfileProvider),
        ),
        data: (p) {
          final completionRequired = widget.completionRequired;
          if (!_hydrated) {
            _hydrated = true;
            _nameController.text =
                isPlaceholderDisplayName(p.displayName) ? '' : p.displayName;
            _baseCurrency = p.baseCurrency;
          }
          if (completionRequired && !_avatarPreviewLoaded) {
            _avatarPreviewLoaded = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _refreshAvatarPreview(p);
            });
          }
          final currency = _baseCurrency ?? p.baseCurrency;
          final tagCaptureLocation =
              ref.watch(captureLocationTaggingProvider);

          return ListView(
            padding: const EdgeInsetsDirectional.all(20),
            children: [
              if (completionRequired) ...[
                _CompletionBlock(subtitle: widget.labels.completionSubtitle),
                const SizedBox(height: 24),
                _AvatarCompletionBlock(
                  labels: widget.labels,
                  displayName: _effectiveDisplayName(p),
                  photoUrl: _avatarPhotoUrl,
                  oauthPreviewUrl: p.avatarUrl == null
                      ? ref
                          .read(profileRepositoryProvider)
                          .oauthAvatarPreviewUrl()
                      : null,
                  oauthPreviewAvailable: ref
                          .read(profileRepositoryProvider)
                          .oauthAvatarPreviewUrl() !=
                      null,
                  busy: _avatarBusy,
                  onUseOAuth: () => _adoptOAuthAvatar(p),
                  onUpload: () => _uploadAvatar(p),
                  onUseInitials: () => _useInitialsAvatar(p),
                ),
                const SizedBox(height: 24),
              ] else ...[
                _AboutBlock(
                  version: _version,
                  versionLabel: widget.labels.versionLabel,
                  tagline: widget.labels.tagline,
                  licensesLabel: widget.labels.licenses,
                  privacyLabel: widget.labels.privacyPolicy,
                ),
                const SizedBox(height: 24),
              ],
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
                  errorText: _nameError,
                ),
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {
                  _dirty = true;
                  _nameError = null;
                }),
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
              if (!completionRequired) ...[
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
                    leading: const Icon(
                      Icons.workspace_premium_outlined,
                      color: AppColors.jadeTeal,
                    ),
                    title: Text(widget.labels.plusTitle),
                    subtitle: Text(
                      widget.labels.plusSubtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.graphite,
                          ),
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
                    leading: const Icon(
                      Icons.lightbulb_outline,
                      color: AppColors.jadeTeal,
                    ),
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
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColors.graphite),
                ),
              ],
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
                onPressed: _saving || _signingOut ? null : _signOut,
                icon: const Icon(Icons.logout),
                label: Text(widget.labels.signOut),
              ),
            ],
          );
        },
      ),
    );
  }

  String _effectiveDisplayName(UserProfile profile) {
    final typed = normalizeDisplayName(_nameController.text);
    if (typed.isNotEmpty && !isPlaceholderDisplayName(typed)) {
      return typed;
    }
    return profile.displayName;
  }

  Future<void> _refreshAvatarPreview(UserProfile profile) async {
    final repo = ref.read(profileRepositoryProvider);
    if (profile.avatarUrl != null && profile.avatarUrl!.isNotEmpty) {
      final signed = await repo.signedAvatarUrl(profile.avatarUrl);
      if (!mounted) return;
      setState(() => _avatarPhotoUrl = signed);
      return;
    }
    if (!mounted) return;
    setState(() => _avatarPhotoUrl = null);
  }

  Future<void> _adoptOAuthAvatar(UserProfile profile) async {
    setState(() => _avatarBusy = true);
    try {
      final updated =
          await ref.read(profileRepositoryProvider).adoptOAuthAvatar();
      ref.invalidate(userProfileProvider);
      if (!mounted) return;
      await _refreshAvatarPreview(updated);
    } catch (e) {
      if (!mounted) return;
      showActionError(
        context,
        ref,
        screen: 'profile',
        action: 'adopt_oauth_avatar',
        error: e,
      );
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  Future<void> _uploadAvatar(UserProfile profile) async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    setState(() => _avatarBusy = true);
    try {
      final updated = await ref
          .read(profileRepositoryProvider)
          .uploadAvatarFromFile(picked.path);
      ref.invalidate(userProfileProvider);
      if (!mounted) return;
      await _refreshAvatarPreview(updated);
    } catch (e) {
      if (!mounted) return;
      showActionError(
        context,
        ref,
        screen: 'profile',
        action: 'upload_avatar',
        error: e,
      );
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  Future<void> _useInitialsAvatar(UserProfile profile) async {
    setState(() => _avatarBusy = true);
    try {
      await ref.read(profileRepositoryProvider).clearAvatar();
      ref.invalidate(userProfileProvider);
      if (!mounted) return;
      setState(() => _avatarPhotoUrl = null);
    } catch (e) {
      if (!mounted) return;
      showActionError(
        context,
        ref,
        screen: 'profile',
        action: 'clear_avatar',
        error: e,
      );
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  Future<void> _save(UserProfile previous) async {
    final validationError = _validateDisplayName();
    if (validationError != null) {
      setState(() => _nameError = validationError);
      return;
    }
    setState(() => _saving = true);
    try {
      final saved = await ref.read(profileRepositoryProvider).update(
            displayName: _nameController.text,
            baseCurrency: _baseCurrency ?? previous.baseCurrency,
          );
      ref.invalidate(userProfileProvider);
      if (!mounted) return;
      setState(() {
        _dirty = false;
        _saving = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(widget.labels.profileSaved)));
      if (widget.completionRequired && !saved.needsIdentityCompletion) {
        context.go(AppRoutes.trips);
      }
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
    if (_signingOut) return;
    setState(() => _signingOut = true);
    try {
      await ref.read(syncWorkerProvider).flush();
      final pendingMedia = await ref
          .read(syncQueueProvider)
          .countPendingMediaUploads();
      if (pendingMedia > 0) {
        if (!mounted) return;
        final discard = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(widget.labels.pendingMediaTitle),
            content: Text(widget.labels.pendingMediaBody(pendingMedia)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(widget.labels.pendingMediaStay),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(widget.labels.pendingMediaDiscard),
              ),
            ],
          ),
        );
        if (discard != true) return;
      }
      await ref.read(tripsRepositoryProvider).clearLocal();
      await ref.read(authRepositoryProvider).signOut();
    } catch (e) {
      if (!mounted) return;
      showActionError(
        context,
        ref,
        screen: 'profile',
        action: 'sign_out',
        error: e,
      );
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  String? _validateDisplayName() {
    final value = normalizeDisplayName(_nameController.text);
    if (value.isEmpty) return widget.labels.displayNameRequired;
    if (isPlaceholderDisplayName(value)) {
      return widget.labels.displayNameReserved;
    }
    return null;
  }
}

class _CompletionBlock extends StatelessWidget {
  const _CompletionBlock({required this.subtitle});

  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.badge_outlined, color: AppColors.jadeTeal),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                subtitle,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppColors.graphite),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AvatarCompletionBlock extends StatelessWidget {
  const _AvatarCompletionBlock({
    required this.labels,
    required this.displayName,
    required this.photoUrl,
    required this.oauthPreviewUrl,
    required this.oauthPreviewAvailable,
    required this.busy,
    required this.onUseOAuth,
    required this.onUpload,
    required this.onUseInitials,
  });

  final ProfileScreenLabels labels;
  final String displayName;
  final String? photoUrl;
  final String? oauthPreviewUrl;
  final bool oauthPreviewAvailable;
  final bool busy;
  final VoidCallback onUseOAuth;
  final VoidCallback onUpload;
  final VoidCallback onUseInitials;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              labels.avatarSection,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 16),
            Center(
              child: VamoAvatar(
                displayName: displayName,
                photoUrl: photoUrl ?? oauthPreviewUrl,
                radius: 36,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                if (oauthPreviewAvailable)
                  OutlinedButton(
                    onPressed: busy ? null : onUseOAuth,
                    child: Text(labels.avatarUseOAuth),
                  ),
                OutlinedButton(
                  onPressed: busy ? null : onUpload,
                  child: Text(labels.avatarUpload),
                ),
                OutlinedButton(
                  onPressed: busy ? null : onUseInitials,
                  child: Text(labels.avatarUseInitials),
                ),
              ],
            ),
          ],
        ),
      ),
    );
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
            Image.asset(BrandAssets.primaryMark, height: 56),
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
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.graphite),
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
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
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
