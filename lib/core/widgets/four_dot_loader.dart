import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Four orbiting dots grow and shrink during each turn. The reserved square
/// keeps surrounding controls stable; reduced-motion settings show still dots.
class FourDotLoader extends StatefulWidget {
  const FourDotLoader({
    this.size = 28,
    this.color,
    this.label = 'Loading',
    super.key,
  });
  final double size;
  final Color? color;
  final String label;

  @override
  State<FourDotLoader> createState() => _FourDotLoaderState();
}

class _FourDotLoaderState extends State<FourDotLoader>
    with SingleTickerProviderStateMixin {
  late final _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context) ||
        !TickerMode.valuesOf(context).enabled;
    if (still) {
      _animation.stop();
      _animation.value = 0;
    } else if (!_animation.isAnimating) {
      _animation.repeat();
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.label,
    liveRegion: true,
    child: SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, _) => CustomPaint(
          painter: _FourDots(
            _animation.value,
            widget.color ?? Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    ),
  );
}

class _FourDots extends CustomPainter {
  const _FourDots(this.progress, this.color);
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final turn = progress * math.pi * 2;
    final orbit = size.shortestSide * 0.29;
    for (var index = 0; index < 4; index++) {
      final angle = turn + index * math.pi / 2 - math.pi / 2;
      final pulse =
          0.72 + 0.28 * (math.sin(turn - index * math.pi / 2) + 1) / 2;
      canvas.drawCircle(
        size.center(Offset.zero) +
            Offset(math.cos(angle), math.sin(angle)) * orbit,
        size.shortestSide * 0.115 * pulse,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_FourDots old) =>
      old.progress != progress || old.color != color;
}
