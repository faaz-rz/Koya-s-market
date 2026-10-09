import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Static, lightweight atmosphere: no blur, animated gradients or extra images.
class CustomerBackdrop extends StatelessWidget {
  const CustomerBackdrop({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(color: colors.canvas),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-1.1, -0.9),
            radius: 1.5,
            colors: [colors.mint, colors.mint.withValues(alpha: 0)],
            stops: const [0, 0.85],
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(1.2, 0.9),
              radius: 1.2,
              colors: [colors.peach, colors.peach.withValues(alpha: 0)],
              stops: const [0, 0.8],
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
