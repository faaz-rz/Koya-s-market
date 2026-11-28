import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../utils/product_grid_layout.dart';

class ProductLoadingSkeleton extends StatelessWidget {
  const ProductLoadingSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    const inset = AppSpacing.md;
    return Semantics(
      label: 'Loading products',
      child: LayoutBuilder(
        builder: (context, constraints) => GridView.builder(
          padding: const EdgeInsets.all(inset),
          itemCount: 6,
          gridDelegate: ProductGridLayout.delegate(
            context,
            constraints.maxWidth - inset * 2,
          ),
          itemBuilder: (context, index) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(child: _SkeletonBlock(radius: AppRadii.md)),
              const SizedBox(height: AppSpacing.xs),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: _SkeletonBlock(
                  width: 64,
                  height: ProductGridLayout.actionHeight(
                    MediaQuery.textScalerOf(context),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              const _SkeletonBlock(width: 52, height: 20),
              const SizedBox(height: AppSpacing.xs),
              const _SkeletonBlock(width: 112, height: 16),
              const SizedBox(height: AppSpacing.xs),
              const _SkeletonBlock(width: 84, height: 16),
            ],
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
