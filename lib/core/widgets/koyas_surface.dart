import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import '../theme/app_spacing.dart';

class KoyasSurface extends StatelessWidget {
  const KoyasSurface({
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.color = AppColors.surface,
    this.radius = AppRadii.xl,
    this.elevated = false,
    this.borderColor = AppColors.outline,
    this.onTap,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final double radius;
  final bool elevated;
  final Color borderColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.resolve(color),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: colors.resolve(borderColor)),
        boxShadow: AppShadows.of(context, elevated: elevated),
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(radius),
        clipBehavior: Clip.antiAlias,
        child: onTap == null
            ? Padding(padding: padding, child: child)
            : InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(radius),
                child: Padding(padding: padding, child: child),
              ),
      ),
    );
  }
}
