import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/price_format.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/koyas_button.dart';
import '../../../core/widgets/koyas_surface.dart';
import '../../products/widgets/product_visual.dart';
import '../../store/providers/store_provider.dart';
import '../widgets/quantity_stepper.dart';

class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  void _increment(BuildContext context, WidgetRef ref, String productId) {
    try {
      ref.read(storeProvider.notifier).addToCart(productId);
    } on StoreValidationException catch (error) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(storeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Your cart')),
      body: store.cartItems.isEmpty
          ? EmptyState(
              icon: Icons.shopping_bag_outlined,
              title: 'Your basket is waiting',
              message:
                  'Add fresh groceries and daily essentials to start your order.',
              action: KoyasButton(
                label: 'Browse products',
                expand: false,
                onPressed: () => context.go('/home'),
              ),
            )
          : SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 840;
                  final items = _CartItems(
                    onIncrement: (id) => _increment(context, ref, id),
                    onAddMore: () => context.go('/home'),
                  );
                  final summary = const _OrderSummary();
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.sm,
                      AppSpacing.lg,
                      AppSpacing.xxxl,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1060),
                        child: wide
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(flex: 3, child: items),
                                  const SizedBox(width: AppSpacing.xxl),
                                  Expanded(flex: 2, child: summary),
                                ],
                              )
                            : Column(
                                children: [
                                  items,
                                  const SizedBox(height: AppSpacing.xxl),
                                  summary,
                                ],
                              ),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

class _CartItems extends ConsumerWidget {
  const _CartItems({required this.onIncrement, required this.onAddMore});

  final ValueChanged<String> onIncrement;
  final VoidCallback onAddMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(storeProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${store.cartCount} ${store.cartCount == 1 ? 'item' : 'items'}',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: AppColors.inkSecondary),
        ),
        const SizedBox(height: AppSpacing.md),
        ...store.cartItems.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: KoyasSurface(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox.square(
                    dimension: 82,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadii.lg),
                      child: ProductVisual(product: item.product, iconSize: 36),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.product.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          item.product.unit,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppColors.inkSecondary),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          formatPrice(item.totalPaise),
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(color: AppColors.brand700),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      QuantityStepper(
                        compact: true,
                        quantity: item.quantity,
                        onIncrement: () => onIncrement(item.product.id),
                        onDecrement: () => ref
                            .read(storeProvider.notifier)
                            .decrementCart(item.product.id),
                      ),
                      TextButton(
                        onPressed: () => ref
                            .read(storeProvider.notifier)
                            .removeFromCart(item.product.id),
                        child: const Text('Remove'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            key: const Key('cart-add-more-items'),
            onPressed: onAddMore,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add more items'),
          ),
        ),
      ],
    );
  }
}

class _OrderSummary extends ConsumerWidget {
  const _OrderSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(storeProvider);
    final shortfall = store.minimumOrderPaise - store.subtotalPaise;
    return KoyasSurface(
      elevated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Bill details', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.lg),
          _SummaryRow(
            label: 'Item total',
            value: formatPrice(store.subtotalPaise + store.savingsPaise),
          ),
          if (store.savingsPaise > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            _SummaryRow(
              label: 'Product savings',
              value: '−${formatPrice(store.savingsPaise)}',
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          const _SummaryRow(label: 'Taxes', value: 'Included'),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Divider(),
          ),
          _SummaryRow(
            label: 'Subtotal',
            value: formatPrice(store.subtotalPaise),
            strong: true,
          ),
          const SizedBox(height: AppSpacing.lg),
          if (shortfall > 0)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.warningSoft,
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              child: Text(
                'Add ${formatPrice(shortfall)} more to reach the ${formatPrice(store.minimumOrderPaise)} minimum.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.warning,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.lg),
          KoyasButton(
            label: 'Choose fulfilment',
            icon: Icons.arrow_forward_rounded,
            onPressed: shortfall <= 0
                ? () => context.push('/checkout/fulfilment')
                : null,
          ),
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: Text(
              'Free pickup · Secure checkout',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.inkSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.strong = false,
  });

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final style = strong
        ? Theme.of(context).textTheme.titleMedium
        : Theme.of(context).textTheme.bodyMedium;
    return Row(
      children: [
        Expanded(child: Text(label, style: style)),
        Text(value, style: style),
      ],
    );
  }
}
