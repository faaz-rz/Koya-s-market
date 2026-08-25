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
    return Semantics(
      button: true,
      label: '$displayName, ${formatPrice(priceProduct.effectivePricePaise)}',
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.xl),
        onTap: () => context.push('/product/${product.id}'),
        child: KoyasSurface(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadii.lg),
                      child: ProductVisual(product: product),
                    ),
                    if (priceProduct.discountPercent > 0)
                      Positioned(
                        left: 8,
                        top: 8,
                        child: _Badge(
                          label: '${priceProduct.discountPercent}% OFF',
                        ),
                      ),
                    Positioned(
                      right: 6,
                      top: 6,
                      child: IconButton.filled(
                        tooltip: 'Save ${product.name}',
                        onPressed: () => ref
                            .read(storeProvider.notifier)
                            .toggleFavorite(product.id),
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.surface,
                          foregroundColor: AppColors.offer,
                        ),
                        icon: Icon(
                          favorite
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              if (product.brand.isNotEmpty) ...[
                Text(
                  product.brand,
                  maxLines: 2,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
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
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                hasMultipleSizes
                    ? '$selectedSize · ${variants.length} options'
                    : [
                        product.unit,
                        if (product.subcategory.isNotEmpty) product.subcategory,
                      ].join(' · '),
                maxLines: 2,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.inkSecondary),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xxs,
                children: [
                  Text(
                    formatPrice(priceProduct.effectivePricePaise),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (priceProduct.discountPricePaise != null)
                    Text(
                      formatPrice(priceProduct.pricePaise),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.inkTertiary,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              if (!available)
                const SizedBox(
                  height: 44,
                  child: Center(child: Text('Out of stock')),
                )
              else if (hasMultipleSizes)
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton(
                    key: Key('choose-size-${product.id}'),
                    onPressed: () => showProductVariantSheet(
                      context: context,
                      family: family!,
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xs,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadii.md),
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(quantity == 0 ? 'ADD' : '$quantity IN CART'),
                        Text(
                          '${variants.length} options',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppColors.brand700),
                        ),
                      ],
                    ),
                  ),
                )
              else if (quantity == 0)
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: FilledButton.tonalIcon(
                    key: Key('add-product-${product.id}'),
                    onPressed: () =>
                        ref.read(storeProvider.notifier).addToCart(product.id),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add'),
                  ),
                )
              else
                Align(
                  alignment: Alignment.center,
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
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.offer,
        borderRadius: BorderRadius.circular(AppRadii.full),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: AppColors.surface),
      ),
    );
  }
}
