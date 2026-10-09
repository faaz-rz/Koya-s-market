import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../utils/product_grid_layout.dart';

class ProductLoadingSkeleton extends StatelessWidget {
  const ProductLoadingSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading products',
      child: LayoutBuilder(
        builder: (context, constraints) => GridView.builder(
          padding: const EdgeInsets.all(AppSpacing.xl),
          itemCount: 6,
          gridDelegate: ProductGridLayout.delegate(
            context,
            constraints.maxWidth - (AppSpacing.xl * 2),
          ),
          itemBuilder: (context, index) => Container(
            padding: EdgeInsets.all(
              ProductGridLayout.usesCompactCards(
                    constraints.maxWidth - (AppSpacing.xl * 2),
                  )
                  ? AppSpacing.sm
                  : AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: AppColors.of(context).surface,
              borderRadius: BorderRadius.circular(AppRadii.xl),
              border: Border.all(color: AppColors.of(context).outline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _SkeletonBlock(radius: AppRadii.lg)),
                const SizedBox(height: AppSpacing.md),
                const _SkeletonBlock(width: 130, height: 18),
                const SizedBox(height: AppSpacing.sm),
                const _SkeletonBlock(width: 76, height: 12),
                const SizedBox(height: AppSpacing.lg),
                const _SkeletonBlock(height: 40, radius: AppRadii.full),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({this.width, this.height, this.radius = AppRadii.sm});

  final double? width;
  final double? height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.of(context).surfaceMuted,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
