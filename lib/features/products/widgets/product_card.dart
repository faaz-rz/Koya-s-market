import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/price_format.dart';
import '../../../core/utils/product_grid_layout.dart';
import '../../cart/widgets/quantity_stepper.dart';
import '../../store/providers/store_provider.dart';
import '../models/product.dart';
import '../product_variants.dart';
import 'product_variant_sheet.dart';
import 'product_visual.dart';

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
        (store) => variants.fold(
          0,
          (total, variant) => total + (store.cartQuantities[variant.id] ?? 0),
        ),
      ),
    );
    final favorite = ref.watch(
      storeProvider.select(
        (store) => store.favoriteProductIds.contains(product.id),
      ),
    );
    final name = family?.name ?? product.name;
    final brand = product.brand.trim();
    final displayName =
        brand.isEmpty || name.toLowerCase().contains(brand.toLowerCase())
        ? name
        : '$brand $name';
    final displayedProduct = family?.representative ?? product;
    final available = variants.any((variant) => variant.isAvailable);
    final showStepper = available && !hasMultipleSizes && quantity > 0;
    final variantLabel = ProductVariants.variantLabel(displayedProduct);
    final packSize = variantLabel == null || variantLabel == 'Pack of 1'
        ? displayedProduct.unit
        : variantLabel;
    final price = formatPrice(displayedProduct.effectivePricePaise);
    final hasDiscount =
        displayedProduct.effectivePricePaise < displayedProduct.pricePaise;
    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final scaler = MediaQuery.textScalerOf(context);
    final packStyle = text.labelMedium?.copyWith(
      color: colors.inkSecondary,
      fontSize: ProductGridLayout.packFontSize,
      height: ProductGridLayout.packLineHeight,
      fontWeight: FontWeight.w700,
    );
    final packLabel = Text(
      packSize,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: packStyle,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final stepperWidth = 120 * scaler.scale(12) / 12;
        final showPackAboveStepper = showStepper && width < stepperWidth + 60;
        final titleSize = ProductGridLayout.titleFontSize(width);
        final priceSize = ProductGridLayout.priceFontSize(width);
        final Widget action;
        if (!available) {
          action = Text(
            'Out of stock',
            maxLines: 2,
            textAlign: TextAlign.end,
            style: packStyle,
          );
        } else if (showStepper) {
          action = QuantityStepper(
            key: Key('quantity-product-${product.id}'),
            quantity: quantity,
            compact: true,
            onIncrement: () =>
                ref.read(storeProvider.notifier).addToCart(product.id),
            onDecrement: () =>
                ref.read(storeProvider.notifier).decrementCart(product.id),
          );
        } else {
          action = SizedBox(
            width: (width * 0.53).clamp(48.0, 104.0),
            height: ProductGridLayout.actionHeight(scaler),
            child: Tooltip(
              message: hasMultipleSizes
                  ? 'Choose size for $displayName'
                  : 'Add $displayName to cart',
              child: OutlinedButton(
                key: Key(
                  hasMultipleSizes
                      ? 'choose-size-${product.id}'
                      : 'add-product-${product.id}',
                ),
                onPressed: hasMultipleSizes
                    ? () => showProductVariantSheet(
                        context: context,
                        family: family!,
                      )
                    : () => ref
                          .read(storeProvider.notifier)
                          .addToCart(product.id),
                style: OutlinedButton.styleFrom(
                  backgroundColor: colors.brandSoft,
                  foregroundColor: colors.brand700,
                  side: BorderSide(color: colors.brand600),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                  ),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(
                      Radius.circular(AppRadii.sm),
                    ),
                  ),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        quantity > 0 ? 'Add · $quantity' : 'Add',
                        style: text.labelLarge?.copyWith(
                          color: colors.brand700,
                          fontSize: ProductGridLayout.addFontSize,
                          height: ProductGridLayout.packLineHeight,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (hasMultipleSizes)
                        Text(
                          '${variants.length} options',
                          style: packStyle?.copyWith(
                            fontSize: ProductGridLayout.optionsFontSize,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        return Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: () => context.push('/product/${product.id}'),
            borderRadius: BorderRadius.circular(AppRadii.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: ProductGridLayout.photoHeight(width),
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      DecoratedBox(
                        position: DecorationPosition.foreground,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppRadii.md),
                          border: Border.all(color: colors.outline),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadii.md),
                          child: ProductVisual(
                            product: displayedProduct,
                            radius: AppRadii.md,
                            iconSize: width < 180 ? 38 : 52,
                          ),
                        ),
                      ),
                      PositionedDirectional(
                        top: 0,
                        end: 0,
                        child: IconButton(
                          tooltip: favorite
                              ? 'Remove $displayName from favourites'
                              : 'Save $displayName',
                          onPressed: () => ref
                              .read(storeProvider.notifier)
                              .toggleFavorite(product.id),
                          visualDensity: VisualDensity.standard,
                          padding: EdgeInsets.zero,
                          icon: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: colors.surface,
                              border: Border.all(color: colors.outline),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(5),
                              child: Icon(
                                favorite
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                                size: 16,
                                color: favorite
                                    ? colors.offer
                                    : colors.inkSecondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (showPackAboveStepper)
                        PositionedDirectional(
                          start: AppSpacing.xs,
                          end: AppSpacing.xs,
                          bottom: AppSpacing.xs,
                          child: Align(
                            alignment: AlignmentDirectional.bottomStart,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: colors.surface,
                                borderRadius: BorderRadius.circular(
                                  AppRadii.sm,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.xs,
                                  vertical: AppSpacing.xxs,
                                ),
                                child: packLabel,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                SizedBox(
                  height: ProductGridLayout.actionHeight(scaler),
                  child: showPackAboveStepper
                      ? Center(child: action)
                      : Row(
                          children: [
                            Expanded(child: packLabel),
                            const SizedBox(width: AppSpacing.xs),
                            if (available) action else Flexible(child: action),
                          ],
                        ),
                ),
                const SizedBox(height: AppSpacing.xs),
                SizedBox(
                  width: double.infinity,
                  height:
                      (scaler.scale(priceSize) *
                              ProductGridLayout.priceLineHeight)
                          .ceilToDouble(),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          price,
                          style: text.titleLarge?.copyWith(
                            color: colors.ink,
                            fontSize: priceSize,
                            height: ProductGridLayout.priceLineHeight,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (hasDiscount) ...[
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            formatPrice(displayedProduct.pricePaise),
                            style: text.bodySmall?.copyWith(
                              color: colors.inkSecondary,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  displayName,
                  maxLines: ProductGridLayout.titleLines,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleSmall?.copyWith(
                    color: colors.ink,
                    fontSize: titleSize,
                    height: ProductGridLayout.titleLineHeight,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
