import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'poi_models.dart';

class PlaceInfo {
  const PlaceInfo({
    required this.name,
    required this.category,
    this.address,
    this.description,
    this.website,
    this.phone,
    this.hours,
    this.rating,
    this.price,
    this.photoUrl,
    this.sourceLabel,
  });

  factory PlaceInfo.fromPoi(PoiSummary poi) {
    return PlaceInfo(
      name: poi.name,
      category: poi.category,
      address: poi.address,
      description: poi.description,
      website: poi.website,
      phone: poi.phone,
      hours: poi.hours,
      rating: poi.rating,
      price: poi.price,
      photoUrl: poi.photoUrl,
      sourceLabel: poi.source == 'foursquare' ? 'Foursquare' : poi.source,
    );
  }

  final String name;
  final PoiCategory category;
  final String? address;
  final String? description;
  final String? website;
  final String? phone;
  final String? hours;
  final double? rating;
  final int? price;
  final String? photoUrl;
  final String? sourceLabel;
}

Future<void> showPlaceInfoCard(
  BuildContext context, {
  required PlaceInfo info,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => PlaceInfoCard(info: info),
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
    final source = info.sourceLabel;

    return SafeArea(
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
                    color: colors.secondary.withValues(alpha: 0.12),
                    borderRadius: shape.controlBorderRadius,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Icon(
                      info.category.icon,
                      color: colors.secondary,
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
                      Text(
                        _categoryLabel(info.category),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceMuted,
                        ),
                      ),
                    ],
                  ),
                ),
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
                if (info.rating case final rating?)
                  _InfoChip('Rating', _rating(rating)),
                if (info.price case final price?)
                  _InfoChip('Price', _price(price)),
                if (info.hours case final hours?) _InfoChip('Hours', hours),
              ],
            ),
            if (info.address case final address?) ...[
              const SizedBox(height: 14),
              _InfoRow(icon: Icons.place_outlined, text: address),
            ],
            if (info.description case final description?) ...[
              const SizedBox(height: 14),
              Text(
                description,
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
    );
  }

  static String _categoryLabel(PoiCategory category) {
    final raw = category.name;
    return raw[0].toUpperCase() + raw.substring(1);
  }

  static String _rating(double rating) => rating.toStringAsFixed(1);

  static String _price(int price) {
    final bounded = price.clamp(1, 4);
    return List.filled(bounded, r'$').join();
  }

  static Future<void> _launchWebsite(String raw) async {
    final value = raw.startsWith(RegExp(r'https?://')) ? raw : 'https://$raw';
    final uri = Uri.tryParse(value);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  static Future<void> _launchPhone(String raw) async {
    final uri = Uri(scheme: 'tel', path: raw);
    await launchUrl(uri);
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
        child: Icon(info.category.icon, color: colors.onSurfaceMuted, size: 42),
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
