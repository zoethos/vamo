import 'dart:io';

import 'package:flutter/material.dart';

import '../snapshot/snapshot_themes.dart';

/// Hero backdrop — user background override, then gradient fallback (S44).
///
/// Future slot: AI-generated destination art (S36+) would sit above the gradient
/// and below or replace the user override per product rules — not built here.
class TripVisualBackdrop extends StatelessWidget {
  const TripVisualBackdrop({
    super.key,
    required this.tripName,
    this.destination,
    this.backgroundImagePath,
    this.borderRadius,
    this.child,
  });

  final String tripName;
  final String? destination;
  final String? backgroundImagePath;
  final BorderRadius? borderRadius;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = SnapshotThemes.resolve(
      destination: destination,
      tripName: tripName,
    );
    final path = backgroundImagePath;
    final hasUserBackground =
        path != null && path.isNotEmpty && File(path).existsSync();

    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasUserBackground)
            Image.file(
              File(path),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _GradientFill(theme: theme),
            )
          else
            _GradientFill(theme: theme),
          if (child != null) child!,
        ],
      ),
    );
  }
}

class _GradientFill extends StatelessWidget {
  const _GradientFill({required this.theme});

  final SnapshotThemePack theme;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: theme.gradient,
        ),
      ),
    );
  }
}
