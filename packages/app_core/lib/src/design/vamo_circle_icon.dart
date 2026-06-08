import 'package:flutter/material.dart';

/// Shared circular icon badge — fill + 2px white ring + soft shadow (S42).
class VamoCircleIcon extends StatelessWidget {
  const VamoCircleIcon({
    super.key,
    required this.diameter,
    required this.child,
    this.backgroundColor,
    this.onTap,
    this.tooltip,
    this.shadow = true,
  });

  static const double borderWidth = 2;
  static const Color borderColor = Colors.white;

  static BoxDecoration decoration({
    required Color fill,
    bool shadow = true,
  }) {
    return BoxDecoration(
      shape: BoxShape.circle,
      color: fill,
      border: Border.all(color: borderColor, width: borderWidth),
      boxShadow: shadow
          ? [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ]
          : null,
    );
  }

  final double diameter;
  final Widget child;
  final Color? backgroundColor;
  final VoidCallback? onTap;
  final String? tooltip;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    Widget content = DecoratedBox(
      decoration: decoration(
        fill: backgroundColor ?? Colors.transparent,
        shadow: shadow,
      ),
      child: SizedBox(
        width: diameter,
        height: diameter,
        child: Center(child: child),
      ),
    );

    if (onTap != null) {
      content = Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: content,
        ),
      );
    }

    if (tooltip != null) {
      content = Tooltip(message: tooltip!, child: content);
    }

    return content;
  }
}
