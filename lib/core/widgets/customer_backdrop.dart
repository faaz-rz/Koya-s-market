import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Static, lightweight atmosphere: no blur, animated gradients or extra images.
class CustomerBackdrop extends StatelessWidget {
  const CustomerBackdrop({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.mint, AppColors.canvas, AppColors.peach],
          stops: [0, 0.52, 1],
        ),
      ),
      child: child,
    );
  }
}
