import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/price_format.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/koyas_button.dart';
import '../../../core/widgets/koyas_surface.dart';
import '../../checkout/models/checkout_models.dart';
import '../../products/widgets/product_visual.dart';
import '../../store/data/supabase_store_repository.dart';
import '../../store/providers/store_provider.dart';
import '../models/order.dart';
import '../widgets/order_status_ui.dart';

/// Shows order information without exposing a multi-step tracking timeline.
class OrderDetailsScreen extends ConsumerWidget {
  const OrderDetailsScreen({required this.orderId, super.key});

  final String orderId;

  CustomerOrder? _find(List<CustomerOrder> orders) {
    for (final order in orders) {
      if (order.id == orderId) return order;
    }
    return null;
  }

  void _goBack(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/orders');
    }
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    try {
      if (AppEnvironment.hasSupabaseConfig) {
        final repository = SupabaseStoreRepository();
        await repository.cancelOrder(orderId);
        final bundle = await repository.loadStore();
        ref.read(storeProvider.notifier).hydrateRemoteBundle(bundle);
      } else {
        ref.read(storeProvider.notifier).cancelOrder(orderId);
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your order has been cancelled.')),
      );
    } on StoreValidationException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final order = _find(ref.watch(storeProvider).orders);
    if (order == null) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          icon: Icons.search_off_rounded,
          title: 'Order not found',
          message: 'This order may no longer be available.',
          action: KoyasButton(
            label: 'View your orders',
            expand: false,
            onPressed: () => context.go('/orders'),
          ),
        ),
      );
    }

    final canCancel =
        order.status == OrderStatus.placed ||
        order.status == OrderStatus.confirmed;
    final statusColor = order.customerStatusColor;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => _goBack(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text('Order #${order.displayReference.replaceFirst('KOY', '')}'),
        actions: [
          IconButton(
            tooltip: 'Go to home',
            onPressed: () => context.go('/home'),
            icon: const Icon(Icons.home_outlined),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppRadii.xl),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            order.status == OrderStatus.readyForPickup
                                ? Icons.storefront_rounded
                                : Icons.shopping_bag_rounded,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.lg),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                order.customerStatusLabel,
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(color: statusColor),
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                order.customerStatusMessage,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  _OrderDetails(order: order),
                  const SizedBox(height: AppSpacing.xxl),
                  Row(
                    children: [
                      if (canCancel)
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _cancel(context, ref),
                            child: const Text('Cancel order'),
                          ),
                        ),
                      if (canCancel) const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: () {
                            ref.read(storeProvider.notifier).reorder(order.id);
                            context.push('/cart');
                          },
                          icon: const Icon(Icons.replay_rounded),
                          label: const Text('Reorder'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.page),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.outline)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: KoyasButton(
                    label: 'Back to home',
                    icon: Icons.home_rounded,
                    onPressed: () => context.go('/home'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrderDetails extends StatelessWidget {
  const _OrderDetails({required this.order});

  final CustomerOrder order;

  @override
  Widget build(BuildContext context) {
    final pickup = order.fulfilmentType == FulfilmentType.pickup;
    final fulfilmentDetails = pickup
        ? 'We will notify you when it is ready for pickup'
        : '${DateFormat('EEE, d MMM').format(order.fulfilmentDate)}\n${order.slotLabel}${order.addressText == null ? '' : '\n${order.addressText}'}';
    return KoyasSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Order details', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                pickup
                    ? Icons.storefront_outlined
                    : Icons.delivery_dining_outlined,
                color: AppColors.brand600,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: Text(fulfilmentDetails)),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Divider(),
          ),
          ...order.items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: ProductVisual.colorFor(item.visualKey),
                      borderRadius: BorderRadius.circular(AppRadii.md),
                    ),
                    child: Icon(
                      ProductVisual.iconFor(item.visualKey),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: Text('${item.name} × ${item.quantity}')),
                  Text(formatPrice(item.totalPaise)),
                ],
              ),
            ),
          ),
          const Divider(),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Text('Total', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              Text(
                formatPrice(order.totalPaise),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
