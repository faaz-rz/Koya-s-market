import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
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
        final compact = constraints.maxWidth < 160;
        final theme = Theme.of(context);
        final textScale = MediaQuery.textScalerOf(
          context,
        ).scale(1).clamp(1.0, 1.5);
        final actionHeight = 44 + ((textScale - 1) * (compact ? 12 : 16));
        final metadata = hasMultipleSizes
            ? '$selectedSize · ${variants.length} options'
            : [
                product.unit,
                if (product.subcategory.isNotEmpty) product.subcategory,
              ].join(' · ');

        final action = !available
            ? SizedBox(
                height: actionHeight,
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'Out of stock',
                      style: compact ? theme.textTheme.labelMedium : null,
                    ),
                  ),
                ),
              )
            : hasMultipleSizes
            ? SizedBox(
                width: double.infinity,
                height: actionHeight,
                child: OutlinedButton(
                  key: Key('choose-size-${product.id}'),
                  onPressed: () => showProductVariantSheet(
                    context: context,
                    family: family!,
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? AppSpacing.xs : AppSpacing.sm,
                      vertical: AppSpacing.xxs,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.md),
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        quantity == 0 ? 'ADD' : '$quantity IN CART',
                        maxLines: 1,
                        style: compact
                            ? theme.textTheme.labelMedium?.copyWith(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              )
                            : null,
                      ),
                      Text(
                        '${variants.length} options',
                        maxLines: 1,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.brand700,
                          fontSize: compact ? 9 : null,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : quantity == 0
            ? SizedBox(
                width: double.infinity,
                height: actionHeight,
                child: FilledButton.tonal(
                  key: Key('add-product-${product.id}'),
                  onPressed: () =>
                      ref.read(storeProvider.notifier).addToCart(product.id),
                  style: FilledButton.styleFrom(
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? AppSpacing.xs : AppSpacing.sm,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_rounded, size: compact ? 15 : 18),
                      const SizedBox(width: AppSpacing.xxs),
                      Text(
                        'ADD',
                        style: compact
                            ? theme.textTheme.labelMedium?.copyWith(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              )
                            : null,
                      ),
                    ],
                  ),
                ),
              )
            : SizedBox(
                width: double.infinity,
                height: actionHeight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: QuantityStepper(
                    quantity: quantity,
                    compact: true,
                    onIncrement: () =>
                        ref.read(storeProvider.notifier).addToCart(product.id),
                    onDecrement: () => ref
                        .read(storeProvider.notifier)
                        .decrementCart(product.id),
                  ),
                ),
              );

        return Semantics(
          button: true,
          label:
              '$displayName, ${formatPrice(priceProduct.effectivePricePaise)}',
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadii.xl),
            onTap: () => context.push('/product/${product.id}'),
            child: KoyasSurface(
              radius: compact ? AppRadii.lg : AppRadii.xl,
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
                                    backgroundColor: AppColors.surface,
                                    foregroundColor: AppColors.offer,
                                    minimumSize: Size.zero,
                                    fixedSize: const Size.square(32),
                                    padding: EdgeInsets.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  )
                                : IconButton.styleFrom(
                                    backgroundColor: AppColors.surface,
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
                      height: 15 * textScale,
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
                      height: 34 * textScale,
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
                      height: 15 * textScale,
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
                    SizedBox(
                      width: double.infinity,
                      height: 22,
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
                                  fontSize: 16,
                                ),
                              ),
                              if (priceProduct.discountPricePaise != null) ...[
                                const SizedBox(width: AppSpacing.xs),
                                Text(
                                  formatPrice(priceProduct.pricePaise),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: AppColors.inkTertiary,
                                    fontSize: 9,
                                    decoration: TextDecoration.lineThrough,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
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
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xxs,
                      children: [
                        Text(
                          formatPrice(priceProduct.effectivePricePaise),
                          style: theme.textTheme.titleLarge,
                        ),
                        if (priceProduct.discountPricePaise != null)
                          Text(
                            formatPrice(priceProduct.pricePaise),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.inkTertiary,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                      ],
                    ),
                  ],
                  SizedBox(height: compact ? AppSpacing.sm : AppSpacing.sm),
                  action,
                ],
              ),
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
