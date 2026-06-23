import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'poi_models.dart';

/// Neutral place-info value object used by live POI suggestions now and saved
/// Visit metadata / map marker sheets later.
class PlaceInfo {
  const PlaceInfo({
    required this.name,
    this.category,
    this.address,
    this.about,
    this.website,
    this.phone,
    this.hours,
    this.rating,
    this.priceLevel,
    this.photoUrl,
    this.sourceLabel,
  });

  factory PlaceInfo.fromPoi(PoiSummary poi) {
    return PlaceInfo(
      name: poi.name,
      category: poi.category,
      address: poi.address,
      about: poi.about,
      website: poi.website,
      phone: poi.phone,
      hours: poi.hours,
      rating: poi.rating,
      priceLevel: poi.priceLevel,
      photoUrl: poi.photoUrl,
      sourceLabel: poi.source == 'foursquare' ? 'Foursquare' : poi.source,
    );
  }

  final String name;
  final PoiCategory? category;
  final String? address;
  final String? about;
  final String? website;
  final String? phone;
  final String? hours;
  final double? rating;
  final int? priceLevel;
  final String? photoUrl;
  final String? sourceLabel;
}

Future<void> showPlaceInfoCard(
  BuildContext context, {
  required PlaceInfo info,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => PlaceInfoCard(info: info),
  );
}

class PlaceInfoCard extends StatelessWidget {
  const PlaceInfoCard({super.key, required this.info});

  final PlaceInfo info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.vamoColors;
    final shape = context.vamoShape;
    final category = info.category;
    final source = info.sourceLabel;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (info.photoUrl case final photoUrl?) ...[
                ClipRRect(
                  borderRadius: shape.cardBorderRadius,
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.network(
                      photoUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _PhotoFallback(info: info),
                      loadingBuilder: (_, child, progress) =>
                          progress == null ? child : _PhotoFallback(info: info),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: VamoPlanTypeColors.visit.withValues(alpha: 0.12),
                      borderRadius: shape.controlBorderRadius,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Icon(
                        category?.icon ?? Icons.place_outlined,
                        color: VamoPlanTypeColors.visit,
                        size: 22,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          info.name,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: colors.onSurface,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (category != null)
                          Text(
                            _categoryLabel(category),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (info.rating case final rating?) _RatingPill(rating),
                ],
              ),
              if (source != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Place data: $source',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceMuted,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (info.priceLevel case final priceLevel?)
                    _InfoChip('Price', _price(priceLevel)),
                  if (info.hours case final hours?) _InfoChip('Hours', hours),
                ],
              ),
              if (info.address case final address?) ...[
                const SizedBox(height: 14),
                _InfoRow(icon: Icons.place_outlined, text: address),
              ],
              if (info.about case final about?) ...[
                const SizedBox(height: 14),
                Text(
                  about,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurface,
                    height: 1.35,
                  ),
                ),
              ],
              if (info.website != null || info.phone != null) ...[
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    if (info.website case final website?)
                      OutlinedButton.icon(
                        onPressed: () => _launchWebsite(website),
                        icon: const Icon(Icons.open_in_new, size: 18),
                        label: const Text('Website'),
                      ),
                    if (info.phone case final phone?)
                      OutlinedButton.icon(
                        onPressed: () => _launchPhone(phone),
                        icon: const Icon(Icons.phone_outlined, size: 18),
                        label: const Text('Call'),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _categoryLabel(PoiCategory category) {
    final raw = category.name;
    return raw[0].toUpperCase() + raw.substring(1);
  }

  static String _price(int priceLevel) {
    final bounded = priceLevel.clamp(1, 4);
    return List.filled(bounded, r'$').join();
  }

  static Future<void> _launchWebsite(String raw) async {
    final value = raw.startsWith(RegExp(r'https?://')) ? raw : 'https://$raw';
    await _launch(value);
  }

  static Future<void> _launchPhone(String raw) async {
    await _launch(Uri(scheme: 'tel', path: raw).toString());
  }

  static Future<void> _launch(String raw) async {
    final uri = Uri.tryParse(raw);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (error, stackTrace) {
      reportAndLog(
        error,
        stackTrace,
        screen: 'place_info',
        action: 'open_link',
        severity: ActionFailureSeverity.degraded,
      );
    }
  }
}

class _RatingPill extends StatelessWidget {
  const _RatingPill(this.rating);

  final double rating;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.vamoColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: VamoPlanTypeColors.train.withValues(alpha: 0.14),
        borderRadius: context.vamoShape.chipBorderRadius,
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: 8,
          vertical: 4,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star, size: 14, color: VamoPlanTypeColors.train),
            const SizedBox(width: 3),
            Text(
              rating.toStringAsFixed(1),
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoFallback extends StatelessWidget {
  const _PhotoFallback({required this.info});

  final PlaceInfo info;

  @override
  Widget build(BuildContext context) {
    final colors = context.vamoColors;
    return ColoredBox(
      color: colors.surfaceMuted,
      child: Center(
        child: Icon(
          info.category?.icon ?? Icons.place_outlined,
          color: colors.onSurfaceMuted,
          size: 42,
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.vamoColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: context.vamoShape.chipBorderRadius,
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: 10,
          vertical: 7,
        ),
        child: Text(
          '$label $value',
          style: theme.textTheme.labelMedium?.copyWith(
            color: colors.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.vamoColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 19, color: colors.onSurfaceMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}
