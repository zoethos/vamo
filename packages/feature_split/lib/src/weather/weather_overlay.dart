import 'dart:math' as math;

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../trips/trips_models.dart';
import 'weather_models.dart';
import 'weather_providers.dart';

/// Flip to `true` when design signs off on the featured-card weather overlay.
const kWeatherFeaturedOverlayEnabled = false;

/// One-line kill-switch for the P1 featured-card overlay.
final weatherFeaturedOverlayEnabledProvider = Provider<bool>(
  (ref) => kWeatherFeaturedOverlayEnabled,
);

/// Atmospheric overlay for the featured trip hero — decorative only (P1).
class WeatherOverlay extends StatelessWidget {
  const WeatherOverlay({
    super.key,
    required this.bucket,
    required this.enabled,
  });

  final ConditionBucket? bucket;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled || bucket == null || bucket == ConditionBucket.unknown) {
      return const SizedBox.shrink();
    }

    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return ExcludeSemantics(
      child: WeatherAnimationGate(
        builder: (animate) => _WeatherOverlayBody(
          bucket: bucket!,
          animate: animate && !reducedMotion,
        ),
      ),
    );
  }
}

/// Featured-card wiring: same gate as the badge + kill-switch + preview fetch.
class TripWeatherOverlay extends ConsumerWidget {
  const TripWeatherOverlay({super.key, required this.trip});

  final TripSummary trip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(weatherFeaturedOverlayEnabledProvider)) {
      return const SizedBox.shrink();
    }
    if (!shouldShowWeatherPreview(
      lifecycle: TripLifecycle.parse(trip.lifecycle),
      startDateIso: trip.startDate,
      now: DateTime.now(),
    )) {
      return const SizedBox.shrink();
    }

    final preview = ref.watch(weatherPreviewProvider(trip.id)).valueOrNull;
    return WeatherOverlay(
      bucket: preview?.bucket,
      enabled: preview != null,
    );
  }
}

typedef WeatherAnimationBuilder = Widget Function(bool animate);

class WeatherAnimationGate extends StatefulWidget {
  const WeatherAnimationGate({super.key, required this.builder});

  final WeatherAnimationBuilder builder;

  @override
  State<WeatherAnimationGate> createState() => _WeatherAnimationGateState();
}

class _WeatherAnimationGateState extends State<WeatherAnimationGate> {
  ScrollPosition? _position;
  bool _onScreen = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _position?.removeListener(_reevaluateVisibility);
    _position = Scrollable.maybeOf(context)?.position;
    _position?.addListener(_reevaluateVisibility);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reevaluateVisibility());
  }

  @override
  void dispose() {
    _position?.removeListener(_reevaluateVisibility);
    super.dispose();
  }

  void _reevaluateVisibility() {
    if (!mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || !box.attached) return;

    var onScreen = true;
    final scrollableContext = Scrollable.maybeOf(context)?.context;
    final scrollableBox =
        scrollableContext?.findRenderObject() as RenderBox?;
    if (scrollableBox != null && scrollableBox.hasSize) {
      final top = box.localToGlobal(Offset.zero, ancestor: scrollableBox).dy;
      final bottom = top + box.size.height;
      onScreen = bottom > 0 && top < scrollableBox.size.height;
    }

    if (onScreen != _onScreen) {
      setState(() => _onScreen = onScreen);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TickerMode(
      enabled: _onScreen,
      child: widget.builder(_onScreen),
    );
  }
}

class _WeatherOverlayBody extends StatelessWidget {
  const _WeatherOverlayBody({
    required this.bucket,
    required this.animate,
  });

  final ConditionBucket bucket;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    return switch (bucket) {
      ConditionBucket.sunny => const _SunnyOverlay(),
      ConditionBucket.cloudy => const _CloudyOverlay(),
      ConditionBucket.rain => _RainOverlay(animate: animate),
      ConditionBucket.thunderstorm => _ThunderstormOverlay(animate: animate),
      ConditionBucket.snow => _SnowOverlay(animate: animate),
      ConditionBucket.fog => const _FogOverlay(),
      ConditionBucket.unknown => const SizedBox.shrink(),
    };
  }
}

class _SunnyOverlay extends StatelessWidget {
  const _SunnyOverlay();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: AlignmentDirectional.topCenter,
              end: AlignmentDirectional.bottomCenter,
              colors: [
                AppColors.mango.withValues(alpha: 0.10),
                Colors.transparent,
              ],
            ),
          ),
        ),
        Align(
          alignment: AlignmentDirectional.topStart,
          child: FractionallySizedBox(
            widthFactor: 0.72,
            heightFactor: 0.55,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: AlignmentDirectional.topStart,
                  radius: 1.05,
                  colors: [
                    AppColors.sunrise.withValues(alpha: 0.16),
                    AppColors.apricot.withValues(alpha: 0.08),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CloudyOverlay extends StatelessWidget {
  const _CloudyOverlay();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topCenter,
          end: AlignmentDirectional.bottomCenter,
          colors: [
            AppColors.mistGray.withValues(alpha: 0.12),
            AppColors.graphite.withValues(alpha: 0.08),
          ],
        ),
      ),
    );
  }
}

class _RainOverlay extends StatefulWidget {
  const _RainOverlay({required this.animate});

  final bool animate;

  @override
  State<_RainOverlay> createState() => _RainOverlayState();
}

class _RainOverlayState extends State<_RainOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant _RainOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  void _syncAnimation() {
    if (widget.animate) {
      _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          painter: _RainPainter(
            progress: widget.animate ? _controller.value : 0.35,
          ),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

class _RainPainter extends CustomPainter {
  _RainPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.deepTeal.withValues(alpha: 0.14)
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round;

    const spacing = 16.0;
    final shift = progress * spacing;
    for (var x = -size.height; x < size.width + size.height; x += spacing) {
      for (var y = -size.height; y < size.height; y += spacing * 1.7) {
        final start = Offset(x + shift, y);
        canvas.drawLine(start, start + const Offset(7, 11), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RainPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _ThunderstormOverlay extends StatefulWidget {
  const _ThunderstormOverlay({required this.animate});

  final bool animate;

  @override
  State<_ThunderstormOverlay> createState() => _ThunderstormOverlayState();
}

class _ThunderstormOverlayState extends State<_ThunderstormOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    );
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant _ThunderstormOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  void _syncAnimation() {
    if (widget.animate) {
      _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final flash = widget.animate && _controller.value > 0.92;
        return Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(
              painter: _RainPainter(
                progress: widget.animate ? _controller.value : 0.35,
              ),
              child: const SizedBox.expand(),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.indigo.withValues(alpha: 0.12),
              ),
            ),
            if (flash)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.warmWhite.withValues(alpha: 0.06),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SnowOverlay extends StatefulWidget {
  const _SnowOverlay({required this.animate});

  final bool animate;

  @override
  State<_SnowOverlay> createState() => _SnowOverlayState();
}

class _SnowOverlayState extends State<_SnowOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_SnowSeed> _seeds;

  @override
  void initState() {
    super.initState();
    final random = math.Random(7);
    _seeds = List.generate(
      18,
      (index) => _SnowSeed(
        x: random.nextDouble(),
        y: random.nextDouble(),
        radius: 1.2 + random.nextDouble() * 1.4,
        drift: random.nextDouble() * 0.08 - 0.04,
      ),
    );
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    );
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant _SnowOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  void _syncAnimation() {
    if (widget.animate) {
      _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          painter: _SnowPainter(
            progress: widget.animate ? _controller.value : 0.42,
            seeds: _seeds,
          ),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

class _SnowSeed {
  const _SnowSeed({
    required this.x,
    required this.y,
    required this.radius,
    required this.drift,
  });

  final double x;
  final double y;
  final double radius;
  final double drift;
}

class _SnowPainter extends CustomPainter {
  _SnowPainter({required this.progress, required this.seeds});

  final double progress;
  final List<_SnowSeed> seeds;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppColors.warmWhite.withValues(alpha: 0.22);
    for (final seed in seeds) {
      final y = ((seed.y + progress) % 1.0) * (size.height + 12) - 6;
      final x = (seed.x + seed.drift * progress) * size.width;
      canvas.drawCircle(Offset(x, y), seed.radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SnowPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _FogOverlay extends StatelessWidget {
  const _FogOverlay();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topCenter,
          end: AlignmentDirectional.bottomCenter,
          stops: const [0.18, 0.48, 0.78],
          colors: [
            Colors.transparent,
            AppColors.mistGray.withValues(alpha: 0.14),
            Colors.transparent,
          ],
        ),
      ),
    );
  }
}
