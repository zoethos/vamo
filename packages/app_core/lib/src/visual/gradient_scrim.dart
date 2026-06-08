import 'package:flutter/material.dart';

/// Bottom scrim so titles stay legible over gradients/photos (S35).
class GradientScrim extends StatelessWidget {
  const GradientScrim({
    super.key,
    this.heightFactor = 0.55,
    this.stops = const [0.0, 0.45, 1.0],
  });

  final double heightFactor;
  final List<double> stops;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.bottomStart,
      child: FractionallySizedBox(
        heightFactor: heightFactor,
        widthFactor: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: AlignmentDirectional.topCenter,
              end: AlignmentDirectional.bottomCenter,
              stops: stops,
              colors: [
                Colors.transparent,
                Colors.black.withValues(alpha: 0.35),
                Colors.black.withValues(alpha: 0.72),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
