import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_breakpoints.dart';
import '../../../core/utils/price_format.dart';
import '../../cart/widgets/quantity_stepper.dart';
import '../../store/providers/store_provider.dart';
import '../models/product.dart';
import '../product_variants.dart';
import '../widgets/product_visual.dart';

class ProductDetailScreen extends ConsumerStatefulWidget {
  const ProductDetailScreen({required this.productId, super.key});

  final String productId;

  @override
  ConsumerState<ProductDetailScreen> createState() =>
      _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  String? _selectedProductId;

  @override
  void didUpdateWidget(covariant ProductDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.productId != widget.productId) _selectedProductId = null;
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(storeProvider);
    final routedProduct = store.productById(widget.productId);
    if (routedProduct == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Product not found')),
      );
    }
    final family = ProductVariants.familyFor(
      product: routedProduct,
      catalogue: store.products,
    );
    final desiredProductId = _selectedProductId ?? widget.productId;
    final product = family.variants.firstWhere(
      (variant) => variant.id == desiredProductId,
      orElse: () => family.representative,
    );
    final quantity = store.cartQuantities[product.id] ?? 0;
    final favorite = store.favoriteProductIds.contains(product.id);
    final title = family.hasMultipleSizes ? family.name : product.name;
    final selectedSize = ProductVariants.variantLabel(product) ?? product.unit;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Product details'),
        actions: [
          IconButton(
            tooltip: 'Cart',
            onPressed: () => context.push('/cart'),
            icon: Badge(
              isLabelVisible: store.cartCount > 0,
              label: Text('${store.cartCount}'),
              child: const Icon(Icons.shopping_bag_outlined),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.outline)),
          ),
          child: quantity == 0
              ? FilledButton.icon(
                  key: const Key('detail-add-to-cart'),
                  onPressed: product.isAvailable
                      ? () => ref
                            .read(storeProvider.notifier)
                            .addToCart(product.id)
                      : null,
                  icon: const Icon(Icons.add_shopping_cart_rounded),
                  label: Text(
                    product.isAvailable ? 'Add to cart' : 'Out of stock',
                  ),
                )
              : Row(
                  children: [
                    Expanded(
                      child: QuantityStepper(
                        quantity: quantity,
                        onIncrement: () => ref
                            .read(storeProvider.notifier)
                            .addToCart(product.id),
                        onDecrement: () => ref
                            .read(storeProvider.notifier)
                            .decrementCart(product.id),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => context.push('/cart'),
                        child: const Text('View cart'),
                      ),
                    ),
                  ],
                ),
        ),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppBreakpoints.medium),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: context.isCompact ? 1.2 : 2.0,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadii.xxl),
                    child: ProductVisual(
                      product: product,
                      radius: AppRadii.xxl,
                      iconSize: 110,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.headlineLarge,
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'Save product',
                      onPressed: () => ref
                          .read(storeProvider.notifier)
                          .toggleFavorite(product.id),
                      icon: Icon(
                        favorite
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  selectedSize,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppColors.inkSecondary,
                  ),
                ),
                if (product.brand.isNotEmpty ||
                    product.subcategory.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    [
                      if (product.brand.isNotEmpty) product.brand,
                      if (product.subcategory.isNotEmpty) product.subcategory,
                    ].join(' · '),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.inkSecondary,
                    ),
                  ),
                ],
                if (family.hasMultipleSizes) ...[
                  const SizedBox(height: AppSpacing.xxl),
                  Text(
                    'Choose quantity',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: family.variants
                        .map((variant) {
                          final label = ProductVariants.variantLabel(variant)!;
                          return ChoiceChip(
                            key: Key('product-size-${variant.id}'),
                            selected: variant.id == product.id,
                            onSelected: (_) =>
                                setState(() => _selectedProductId = variant.id),
                            label: Text(
                              '$label · ${formatPrice(variant.effectivePricePaise)}'
                              '${variant.isAvailable ? '' : ' · Out of stock'}',
                            ),
                          );
                        })
                        .toList(growable: false),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Text(
                      formatPrice(product.effectivePricePaise),
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    if (product.discountPricePaise != null) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        formatPrice(product.pricePaise),
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: AppColors.inkTertiary,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.errorSoft,
                          borderRadius: BorderRadius.circular(AppRadii.full),
                        ),
                        child: Text(
                          '${product.discountPercent}% OFF',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(color: AppColors.offer),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.xxl),
                Text(
                  'About this product',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  product.description,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                if ((product.billingName.isNotEmpty &&
                        product.billingName != product.name) ||
                    product.itemCode.isNotEmpty ||
                    product.barcode.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _ProductIdentity(product: product),
                ],
                if (product.imageAttribution.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    product.imageAttribution,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.inkTertiary,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.xxl),
                const _FeatureRow(
                  icon: Icons.verified_outlined,
                  title: 'Quality checked',
                  detail: 'Verified by the store team before packing',
                ),
                const SizedBox(height: AppSpacing.md),
                _FeatureRow(
                  icon: Icons.inventory_2_outlined,
                  title: product.isAvailable
                      ? 'Stock available'
                      : 'Currently out of stock',
                  detail: product.isAvailable
                      ? 'Availability is rechecked securely at checkout'
                      : 'Choose another quantity or check again later',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductIdentity extends StatelessWidget {
  const _ProductIdentity({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      if (product.billingName.isNotEmpty && product.billingName != product.name)
        ('Billing item', product.billingName),
      if (product.itemCode.isNotEmpty) ('Item code', product.itemCode),
      if (product.barcode.isNotEmpty) ('Barcode', product.barcode),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < rows.length; index++) ...[
            Text(
              rows[index].$1,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: AppColors.inkTertiary),
            ),
            Text(rows[index].$2, style: Theme.of(context).textTheme.bodyMedium),
            if (index != rows.length - 1) const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: const BoxDecoration(
            color: AppColors.brandSoft,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: AppColors.brand700),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              Text(
                detail,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.inkSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
