import 'package:app_core/app_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
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
    required this.avatarUsePhoto,
    required this.avatarRemovePhoto,
    required this.avatarRemovePhotoTitle,
    required this.avatarRemovePhotoBody,
    required this.avatarRemovePhotoCancel,
    required this.avatarRemovePhotoConfirm,
    required this.avatarInitialsLabel,
    required this.avatarInitialsHint,
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
  final String avatarUsePhoto;
  final String avatarRemovePhoto;
  final String avatarRemovePhotoTitle;
  final String avatarRemovePhotoBody;
  final String avatarRemovePhotoCancel;
  final String avatarRemovePhotoConfirm;
  final String avatarInitialsLabel;
  final String avatarInitialsHint;
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
  final _avatarInitialsController = TextEditingController();
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
    _avatarInitialsController.dispose();
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
            _avatarInitialsController.text = p.avatarInitials ?? '';
            _baseCurrency = p.baseCurrency;
          }
          if (!_avatarPreviewLoaded) {
            _avatarPreviewLoaded = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _refreshAvatarPreview(p);
            });
          }
          final currency = _baseCurrency ?? p.baseCurrency;
          final tagCaptureLocation = ref.watch(captureLocationTaggingProvider);

          if (completionRequired) {
            return _buildCompletionBody(
              context,
              p: p,
              currency: currency,
            );
          }
          return _buildSteadyStateBody(
            context,
            p: p,
            currency: currency,
            tagCaptureLocation: tagCaptureLocation,
          );
        },
      ),
    );
  }

  Widget _buildCompletionBody(
    BuildContext context, {
    required UserProfile p,
    required String currency,
  }) {
    return ListView(
      padding: const EdgeInsetsDirectional.all(20),
      children: [
        _CompletionBlock(subtitle: widget.labels.completionSubtitle),
        const SizedBox(height: 24),
        _avatarBlock(p),
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
          key: const Key('profileDisplayNameField'),
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
  }

  Widget _buildSteadyStateBody(
    BuildContext context, {
    required UserProfile p,
    required String currency,
    required bool tagCaptureLocation,
  }) {
    final oauthPreview =
        ref.read(profileRepositoryProvider).oauthAvatarPreviewUrl();
    final headerPhotoUrl =
        _avatarPhotoUrl ?? (p.avatarUrl == null ? oauthPreview : null);

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsetsDirectional.all(20),
            children: [
              _ProfileHeader(
                displayName: _effectiveDisplayName(p),
                initials: _avatarInitialsController.text,
                photoUrl: headerPhotoUrl,
                tagline: widget.labels.tagline,
                onAvatarTap: () => _showAvatarActionsSheet(p),
              ),
              const SizedBox(height: 24),
              _SettingsSection(
                title: widget.labels.profileSection,
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 0),
                    child: TextFormField(
                      key: const Key('profileDisplayNameField'),
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: widget.labels.displayName,
                        hintText: widget.labels.displayNameHint,
                        errorText: _nameError,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        focusedErrorBorder: InputBorder.none,
                      ),
                      textCapitalization: TextCapitalization.words,
                      onChanged: (_) => setState(() {
                        _dirty = true;
                        _nameError = null;
                      }),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 8),
                    child: DropdownButtonFormField<String>(
                      initialValue: currency,
                      decoration: InputDecoration(
                        labelText: widget.labels.defaultCurrency,
                        helperText: widget.labels.defaultCurrencyHelper,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
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
                  ),
                ],
              ),
              _SettingsSection(
                title: widget.labels.appearanceSection,
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.all(16),
                    child: SegmentedButton<VamoThemePreference>(
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
                  ),
                ],
              ),
              _SettingsSection(
                title: widget.labels.privacySection,
                children: [
                  SwitchListTile.adaptive(
                    contentPadding: const EdgeInsetsDirectional.symmetric(
                      horizontal: 16,
                    ),
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
                ],
              ),
              _SettingsSection(
                title: widget.labels.billingSection,
                children: [
                  ListTile(
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
                  ListTile(
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
                ],
              ),
              if (kDebugMode) ...[
                _SettingsSection(
                  title: widget.labels.devLocaleSection,
                  children: [
                    Padding(
                      padding: const EdgeInsetsDirectional.all(16),
                      child: SegmentedButton<DevLocaleOverride>(
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
                    ),
                  ],
                ),
              ],
              _SettingsSection(
                title: widget.labels.analyticsSection,
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.all(16),
                    child: Text(
                      Env.posthogApiKey.isEmpty
                          ? widget.labels.analyticsHint
                          : widget.labels.posthogActive,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.graphite,
                          ),
                    ),
                  ),
                ],
              ),
              _SettingsSection(
                title: widget.labels.aboutSection,
                children: [
                  if (_version != null)
                    ListTile(
                      title: Text('${widget.labels.versionLabel} $_version'),
                    ),
                  ListTile(
                    title: Text(widget.labels.licenses),
                    trailing: Icon(
                      Directionality.of(context) == TextDirection.rtl
                          ? Icons.chevron_left
                          : Icons.chevron_right,
                    ),
                    onTap: () => showLicensePage(
                      context: context,
                      applicationName: 'Vamo',
                      applicationVersion: _version ?? '',
                    ),
                  ),
                  ListTile(
                    title: Text(widget.labels.privacyPolicy),
                    trailing: Icon(
                      Directionality.of(context) == TextDirection.rtl
                          ? Icons.chevron_left
                          : Icons.chevron_right,
                    ),
                    onTap: () async {
                      final uri = Uri.parse('https://vamo.world/privacy');
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        );
                      }
                    },
                  ),
                ],
              ),
              _SettingsSection(
                title: 'Account',
                children: [
                  ListTile(
                    leading: const Icon(Icons.logout),
                    title: Text(widget.labels.signOut),
                    enabled: !_saving && !_signingOut,
                    onTap: _saving || _signingOut ? null : _signOut,
                  ),
                ],
              ),
            ],
          ),
        ),
        _SaveBar(
          dirty: _dirty,
          saving: _saving,
          label: widget.labels.saveChanges,
          onSave: () => _save(p),
        ),
      ],
    );
  }

  void _showAvatarActionsSheet(UserProfile profile) {
    final oauthPreview =
        ref.read(profileRepositoryProvider).oauthAvatarPreviewUrl();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        void dismissThen(VoidCallback action) {
          Navigator.of(sheetContext).pop();
          action();
        }

        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: SingleChildScrollView(
            child: _AvatarCompletionBlock(
              labels: widget.labels,
              displayName: _effectiveDisplayName(profile),
              initials: _avatarInitialsController.text,
              photoUrl: _avatarPhotoUrl,
              oauthPreviewUrl:
                  profile.avatarUrl == null ? oauthPreview : null,
              oauthPreviewAvailable: oauthPreview != null,
              storedPhotoAvailable:
                  profile.avatarUrl != null && profile.avatarUrl!.isNotEmpty,
              busy: _avatarBusy,
              onUseOAuth: () => dismissThen(() => _adoptOAuthAvatar(profile)),
              onUpload: () => dismissThen(() => _uploadAvatar(profile)),
              onUseInitials: () => dismissThen(() => _useInitialsAvatar(profile)),
              onUsePhoto: () => dismissThen(() => _usePhotoAvatar(profile)),
              onRemovePhoto: () => dismissThen(() => _removeAvatarPhoto(profile)),
              initialsController: _avatarInitialsController,
              onInitialsChanged: (_) => setState(() {}),
            ),
          ),
        );
      },
    );
  }

  String _effectiveDisplayName(UserProfile profile) {
    final typed = normalizeDisplayName(_nameController.text);
    if (typed.isNotEmpty && !isPlaceholderDisplayName(typed)) {
      return typed;
    }
    return profile.displayName;
  }

  /// Avatar management card — shown both in the completion flow and the
  /// steady-state profile so an existing user can change their picture.
  Widget _avatarBlock(UserProfile p) {
    final oauthPreview =
        ref.read(profileRepositoryProvider).oauthAvatarPreviewUrl();
    return _AvatarCompletionBlock(
      labels: widget.labels,
      displayName: _effectiveDisplayName(p),
      initials: _avatarInitialsController.text,
      photoUrl: _avatarPhotoUrl,
      oauthPreviewUrl: p.avatarUrl == null ? oauthPreview : null,
      oauthPreviewAvailable: oauthPreview != null,
      storedPhotoAvailable: p.avatarUrl != null && p.avatarUrl!.isNotEmpty,
      busy: _avatarBusy,
      onUseOAuth: () => _adoptOAuthAvatar(p),
      onUpload: () => _uploadAvatar(p),
      onUseInitials: () => _useInitialsAvatar(p),
      onUsePhoto: () => _usePhotoAvatar(p),
      onRemovePhoto: () => _removeAvatarPhoto(p),
      initialsController: _avatarInitialsController,
      onInitialsChanged: (_) => setState(() {}),
    );
  }

  Future<void> _refreshAvatarPreview(UserProfile profile) async {
    final repo = ref.read(profileRepositoryProvider);
    if (profile.activeAvatarStoragePath != null &&
        profile.activeAvatarStoragePath!.isNotEmpty) {
      final signed =
          await repo.signedAvatarUrl(profile.activeAvatarStoragePath);
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
      final updated = await ref
          .read(profileRepositoryProvider)
          .useInitialsAvatar(_avatarInitialsController.text);
      ref.invalidate(userProfileProvider);
      if (!mounted) return;
      _avatarInitialsController.text = updated.avatarInitials ?? '';
      setState(() => _avatarPhotoUrl = null);
    } catch (e) {
      if (!mounted) return;
      showActionError(
        context,
        ref,
        screen: 'profile',
        action: 'use_initials_avatar',
        error: e,
      );
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  Future<void> _usePhotoAvatar(UserProfile profile) async {
    setState(() => _avatarBusy = true);
    try {
      final updated =
          await ref.read(profileRepositoryProvider).usePhotoAvatar();
      ref.invalidate(userProfileProvider);
      if (!mounted) return;
      await _refreshAvatarPreview(updated);
    } catch (e) {
      if (!mounted) return;
      showActionError(
        context,
        ref,
        screen: 'profile',
        action: 'use_photo_avatar',
        error: e,
      );
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  Future<void> _removeAvatarPhoto(UserProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.labels.avatarRemovePhotoTitle),
        content: Text(widget.labels.avatarRemovePhotoBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(widget.labels.avatarRemovePhotoCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(widget.labels.avatarRemovePhotoConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _avatarBusy = true);
    try {
      final updated = await ref.read(profileRepositoryProvider).clearAvatar();
      ref.invalidate(userProfileProvider);
      if (!mounted) return;
      _avatarInitialsController.text = updated.avatarInitials ?? '';
      setState(() => _avatarPhotoUrl = null);
    } catch (e) {
      if (!mounted) return;
      showActionError(
        context,
        ref,
        screen: 'profile',
        action: 'remove_avatar_photo',
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
      final pendingMedia =
          await ref.read(syncQueueProvider).countPendingMediaUploads();
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
    required this.initials,
    required this.photoUrl,
    required this.oauthPreviewUrl,
    required this.oauthPreviewAvailable,
    required this.storedPhotoAvailable,
    required this.busy,
    required this.onUseOAuth,
    required this.onUpload,
    required this.onUseInitials,
    required this.onUsePhoto,
    required this.onRemovePhoto,
    required this.initialsController,
    required this.onInitialsChanged,
  });

  final ProfileScreenLabels labels;
  final String displayName;
  final String initials;
  final String? photoUrl;
  final String? oauthPreviewUrl;
  final bool oauthPreviewAvailable;
  final bool storedPhotoAvailable;
  final bool busy;
  final VoidCallback onUseOAuth;
  final VoidCallback onUpload;
  final VoidCallback onUseInitials;
  final VoidCallback onUsePhoto;
  final VoidCallback onRemovePhoto;
  final TextEditingController initialsController;
  final ValueChanged<String> onInitialsChanged;

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
                initials: initials,
                photoUrl: photoUrl ?? oauthPreviewUrl,
                radius: 36,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('profileAvatarInitialsField'),
              controller: initialsController,
              decoration: InputDecoration(
                labelText: labels.avatarInitialsLabel,
                hintText: preferredAvatarInitials(
                      preferredInitials: null,
                      displayName: displayName,
                    ) ??
                    labels.avatarInitialsHint,
                helperText: labels.avatarInitialsHint,
                counterText: '',
              ),
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                LengthLimitingTextInputFormatter(4),
                FilteringTextInputFormatter.deny(RegExp(r'\s')),
              ],
              onChanged: onInitialsChanged,
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
                if (storedPhotoAvailable)
                  OutlinedButton(
                    onPressed: busy ? null : onUsePhoto,
                    child: Text(labels.avatarUsePhoto),
                  ),
                if (storedPhotoAvailable)
                  OutlinedButton(
                    onPressed: busy ? null : onRemovePhoto,
                    child: Text(labels.avatarRemovePhoto),
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

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.displayName,
    required this.initials,
    required this.photoUrl,
    required this.tagline,
    required this.onAvatarTap,
  });

  final String displayName;
  final String initials;
  final String? photoUrl;
  final String tagline;
  final VoidCallback onAvatarTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            key: const Key('profileHeaderAvatar'),
            onTap: onAvatarTap,
            customBorder: const CircleBorder(),
            child: VamoAvatar(
              displayName: displayName,
              initials: initials,
              photoUrl: photoUrl,
              radius: 40,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          displayName,
          key: const Key('profileHeaderDisplayName'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AppColors.ink,
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          tagline,
          key: const Key('profileHeaderTagline'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.graphite,
              ),
        ),
      ],
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          Card(
            clipBehavior: Clip.antiAlias,
            margin: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: AppColors.graphite.withValues(alpha: 0.2),
                    ),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SaveBar extends StatelessWidget {
  const _SaveBar({
    required this.dirty,
    required this.saving,
    required this.label,
    required this.onSave,
  });

  final bool dirty;
  final bool saving;
  final String label;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: AppColors.graphite.withValues(alpha: 0.2),
              ),
            ),
          ),
          child: Padding(
            key: const Key('profileSaveBar'),
            padding: const EdgeInsetsDirectional.all(20),
            child: FilledButton(
              onPressed: saving || !dirty ? null : onSave,
              child: saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(label),
            ),
          ),
        ),
      ),
    );
  }
}
