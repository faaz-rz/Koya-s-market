import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/price_format.dart';
import '../../store/providers/store_provider.dart';
import '../models/product.dart';
import '../product_variants.dart';
import 'product_visual.dart';

Future<void> showProductVariantSheet({
  required BuildContext context,
  required ProductFamily family,
}) {
  FocusScope.of(context).unfocus();
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    sheetAnimationStyle: AppMotion.sheetStyle(context),
    builder: (_) => _ProductVariantSheet(family: family),
  );
}

class _ProductVariantSheet extends ConsumerWidget {
  const _ProductVariantSheet({required this.family});

  final ProductFamily family;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scale = math.max(
      1.0,
      MediaQuery.textScalerOf(context).scale(14) / 14,
    );
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: LayoutBuilder(
          builder: (context, constraints) => SizedBox(
            height: math.min(
              constraints.maxHeight * 0.88,
              (190.0 + family.variants.length * 112.0) * scale,
            ),
            child: Material(
              color: AppColors.surface,
              clipBehavior: Clip.antiAlias,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppRadii.xxl),
              ),
              child: SafeArea(
                top: false,
                child: CustomScrollView(
                  key: const Key('variant-sheet-scroll'),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: Container(
                              width: 42,
                              height: 4,
                              margin: const EdgeInsets.only(top: AppSpacing.sm),
                              decoration: BoxDecoration(
                                color: AppColors.outlineStrong,
                                borderRadius: BorderRadius.circular(
                                  AppRadii.full,
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.xl,
                              AppSpacing.lg,
                              AppSpacing.sm,
                              AppSpacing.md,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Choose a pack size',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.headlineMedium,
                                      ),
                                      const SizedBox(height: AppSpacing.xs),
                                      Text(
                                        family.name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              color: AppColors.inkSecondary,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  key: const Key('close-variant-sheet'),
                                  tooltip: 'Close',
                                  onPressed: () => Navigator.of(context).pop(),
                                  icon: const Icon(Icons.close_rounded),
                                ),
                              ],
                            ),
                          ),
                          const Divider(),
                        ],
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      sliver: SliverList.separated(
                        itemCount: family.variants.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, index) =>
                            _VariantRow(product: family.variants[index]),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VariantRow extends ConsumerWidget {
  const _VariantRow({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quantity = ref.watch(
      storeProvider.select((store) => store.cartQuantities[product.id] ?? 0),
    );
    final size = ProductVariants.variantLabel(product) ?? product.unit;
    return Semantics(
      label:
          '$size, ${formatPrice(product.effectivePricePaise)}'
          '${product.isAvailable ? '' : ', out of stock'}',
      child: Container(
        key: Key('variant-option-${product.id}'),
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.lg),
          border: Border.all(color: AppColors.outline),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked =
                constraints.maxWidth < 320 ||
                MediaQuery.textScalerOf(context).scale(14) > 20;
            final details = Row(
              children: [
                SizedBox.square(
                  dimension: stacked ? 60 : 78,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    child: ProductVisual(product: product, radius: AppRadii.md),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        size,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Wrap(
                        spacing: AppSpacing.xs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            formatPrice(product.effectivePricePaise),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (product.discountPricePaise != null)
                            Text(
                              formatPrice(product.pricePaise),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: AppColors.inkTertiary,
                                    decoration: TextDecoration.lineThrough,
                                  ),
                            ),
                        ],
                      ),
                      if (product.discountPercent > 0) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          '${product.discountPercent}% OFF',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: AppColors.offer,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ] else if (!product.isAvailable) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Out of stock',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(color: AppColors.error),
                        ),
                      ],
                    ],
                  ),
                ),
                if (!stacked) ...[
                  const SizedBox(width: AppSpacing.sm),
                  _VariantCartControl(product: product, quantity: quantity),
                ],
              ],
            );
            return stacked
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      details,
                      const SizedBox(height: AppSpacing.sm),
                      Align(
                        alignment: Alignment.centerRight,
                        child: _VariantCartControl(
                          product: product,
                          quantity: quantity,
                        ),
                      ),
                    ],
                  )
                : details;
          },
        ),
      ),
    );
  }
}

class _VariantCartControl extends ConsumerWidget {
  const _VariantCartControl({required this.product, required this.quantity});

  final Product product;
  final int quantity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(storeProvider.notifier);
    if (quantity == 0) {
      return SizedBox(
        width: 88,
        height: 48,
        child: OutlinedButton(
          key: Key('variant-add-${product.id}'),
          onPressed: product.isAvailable
              ? () => controller.addToCart(product.id)
              : null,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(88, 48),
            padding: EdgeInsets.zero,
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
          ),
          child: const Text('ADD'),
        ),
      );
    }
    return Container(
      key: Key('variant-quantity-${product.id}'),
      constraints: const BoxConstraints(minWidth: 120, minHeight: 48),
      decoration: BoxDecoration(
        color: AppColors.brand600,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CounterButton(
            key: Key('variant-remove-${product.id}'),
            tooltip: 'Remove one $sizeLabel',
            icon: Icons.remove_rounded,
            onPressed: () => controller.decrementCart(product.id),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            child: Text(
              '$quantity',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: AppColors.surface,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          _CounterButton(
            key: Key('variant-increment-${product.id}'),
            tooltip: 'Add one $sizeLabel',
            icon: Icons.add_rounded,
            onPressed: quantity < product.stockQuantity
                ? () => controller.addToCart(product.id)
                : null,
          ),
        ],
      ),
    );
  }

  String get sizeLabel => ProductVariants.variantLabel(product) ?? product.unit;
}

class _CounterButton extends StatelessWidget {
  const _CounterButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: onPressed != null,
        label: tooltip,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppRadii.sm),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(
              icon,
              size: 18,
              color: onPressed == null ? AppColors.brand300 : AppColors.surface,
            ),
          ),
        ),
      ),
    );
  }
}
