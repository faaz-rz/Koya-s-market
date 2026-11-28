import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class CustomerBackdrop extends StatelessWidget {
  const CustomerBackdrop({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(colors.canvas, colors.mint, 0.35)!,
            colors.canvas,
          ],
          stops: const [0, 0.26],
        ),
      ),
      child: child,
    );
  }
}
