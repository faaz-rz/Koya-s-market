import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/product_grid_layout.dart';
import '../../../core/utils/price_format.dart';
import '../../../core/widgets/koyas_surface.dart';
import '../../cart/widgets/quantity_stepper.dart';
import '../../store/providers/store_provider.dart';
import '../models/product.dart';
import '../product_variants.dart';
import 'product_visual.dart';
import 'product_variant_sheet.dart';

class ProductCard extends ConsumerWidget {
  const ProductCard({required this.product, this.family, super.key});

  final Product product;
  final ProductFamily? family;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final variants = family?.variants ?? <Product>[product];
    final hasMultipleSizes = variants.length > 1;
    final quantity = ref.watch(
      storeProvider.select(
        (value) => variants.fold(
          0,
          (total, variant) => total + (value.cartQuantities[variant.id] ?? 0),
        ),
      ),
    );
    final favorite = ref.watch(
      storeProvider.select(
        (value) => value.favoriteProductIds.contains(product.id),
      ),
    );
    final displayName = family?.name ?? product.name;
    final priceProduct = family?.representative ?? product;
    final available = variants.any((variant) => variant.isAvailable);
    final selectedSize =
        ProductVariants.variantLabel(priceProduct) ?? priceProduct.unit;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < ProductGridLayout.compactCardBreakpoint;
        final theme = Theme.of(context);
        final textScaler = MediaQuery.textScalerOf(context);
        const actionSize = 48.0;
        final metadata = hasMultipleSizes
            ? '$selectedSize · ${variants.length} options'
            : [
                product.unit,
                if (product.subcategory.isNotEmpty) product.subcategory,
              ].join(' · ');

        final showQuantityStepper =
            available && !hasMultipleSizes && quantity > 0;
        final quickAction = !available
            ? Semantics(
                label: 'Out of stock',
                child: Tooltip(
                  message: 'Out of stock',
                  child: SizedBox.square(
                    dimension: actionSize,
                    child: Icon(
                      Icons.remove_shopping_cart_outlined,
                      color: AppColors.inkTertiary,
                      size: compact ? 18 : 20,
                    ),
                  ),
                ),
              )
            : hasMultipleSizes
            ? SizedBox.square(
                dimension: actionSize,
                child: IconButton.filled(
                  key: Key('choose-size-${product.id}'),
                  tooltip: 'Choose size for $displayName',
                  onPressed: () => showProductVariantSheet(
                    context: context,
                    family: family!,
                  ),
                  style: IconButton.styleFrom(
                    minimumSize: Size.zero,
                    fixedSize: Size.square(actionSize),
                    padding: EdgeInsets.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    backgroundColor: AppColors.brand600,
                    foregroundColor: AppColors.surface,
                  ),
                  icon: Badge.count(
                    count: quantity,
                    isLabelVisible: quantity > 0,
                    child: Icon(Icons.add_rounded, size: compact ? 20 : 22),
                  ),
                ),
              )
            : showQuantityStepper
            ? null
            : SizedBox.square(
                dimension: actionSize,
                child: IconButton.filled(
                  key: Key('add-product-${product.id}'),
                  tooltip: 'Add $displayName to cart',
                  onPressed: () =>
                      ref.read(storeProvider.notifier).addToCart(product.id),
                  style: IconButton.styleFrom(
                    minimumSize: Size.zero,
                    fixedSize: Size.square(actionSize),
                    padding: EdgeInsets.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    backgroundColor: AppColors.brand600,
                    foregroundColor: AppColors.surface,
                  ),
                  icon: Icon(Icons.add_rounded, size: compact ? 20 : 22),
                ),
              );

        return Semantics(
          button: true,
          label:
              '$displayName, ${formatPrice(priceProduct.effectivePricePaise)}',
          child: KoyasSurface(
            onTap: () => context.push('/product/${product.id}'),
            radius: compact ? AppRadii.lg : AppRadii.xxl,
            borderColor: AppColors.surface,
            padding: EdgeInsets.all(compact ? AppSpacing.sm : AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(
                          compact ? AppRadii.md : AppRadii.lg,
                        ),
                        child: ProductVisual(
                          product: product,
                          radius: compact ? AppRadii.md : AppRadii.lg,
                          iconSize: compact ? 36 : 58,
                        ),
                      ),
                      if (priceProduct.discountPercent > 0)
                        Positioned(
                          left: compact ? 4 : 8,
                          top: compact ? 4 : 8,
                          child: _Badge(
                            label: '${priceProduct.discountPercent}% OFF',
                            compact: compact,
                          ),
                        ),
                      Positioned(
                        right: compact ? 3 : 6,
                        top: compact ? 3 : 6,
                        child: IconButton.filled(
                          tooltip: 'Save ${product.name}',
                          onPressed: () => ref
                              .read(storeProvider.notifier)
                              .toggleFavorite(product.id),
                          style: compact
                              ? IconButton.styleFrom(
                                  backgroundColor: AppColors.surface.withValues(
                                    alpha: 0.88,
                                  ),
                                  foregroundColor: AppColors.offer,
                                  minimumSize: Size.zero,
                                  fixedSize: const Size.square(48),
                                  padding: EdgeInsets.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                )
                              : IconButton.styleFrom(
                                  backgroundColor: AppColors.surface.withValues(
                                    alpha: 0.88,
                                  ),
                                  foregroundColor: AppColors.offer,
                                ),
                          icon: Icon(
                            favorite
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            size: compact ? 16 : 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: compact ? AppSpacing.sm : AppSpacing.md),
                if (compact) ...[
                  SizedBox(
                    height: textScaler.scale(10) * 1.5,
                    child: product.brand.isEmpty
                        ? null
                        : Text(
                            product.brand,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: AppColors.brand700,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  SizedBox(
                    height: textScaler.scale(13) * 2.5 + 2,
                    child: Text(
                      displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 13,
                        height: 1.25,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  SizedBox(
                    height: textScaler.scale(10) * 1.5,
                    child: Text(
                      metadata,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.inkSecondary,
                        fontSize: 10,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ] else ...[
                  if (product.brand.isNotEmpty) ...[
                    Text(
                      product.brand,
                      maxLines: 2,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: AppColors.brand700,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                  ],
                  Text(
                    displayName,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    metadata,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.inkSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  height: actionSize,
                  child: Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  formatPrice(priceProduct.effectivePricePaise),
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontSize: compact ? 16 : null,
                                  ),
                                ),
                                if (priceProduct.discountPricePaise !=
                                    null) ...[
                                  const SizedBox(width: AppSpacing.xs),
                                  Text(
                                    formatPrice(priceProduct.pricePaise),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: AppColors.inkTertiary,
                                      fontSize: compact ? 9 : null,
                                      decoration: TextDecoration.lineThrough,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (quickAction != null) ...[
                        const SizedBox(width: AppSpacing.xs),
                        quickAction,
                      ],
                    ],
                  ),
                ),
                AnimatedSize(
                  duration: AppMotion.duration(
                    context,
                    const Duration(milliseconds: 160),
                  ),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.bottomCenter,
                  child: showQuantityStepper
                      ? Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.xs),
                          child: SizedBox(
                            key: Key('quantity-product-${product.id}'),
                            width: double.infinity,
                            height: actionSize,
                            child: QuantityStepper(
                              quantity: quantity,
                              compact: true,
                              onIncrement: () => ref
                                  .read(storeProvider.notifier)
                                  .addToCart(product.id),
                              onDecrement: () => ref
                                  .read(storeProvider.notifier)
                                  .decrementCart(product.id),
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.compact});

  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 5 : 8,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: AppColors.offer,
        borderRadius: BorderRadius.circular(AppRadii.full),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: AppColors.surface,
          fontSize: compact ? 8 : null,
        ),
      ),
    );
  }
}
