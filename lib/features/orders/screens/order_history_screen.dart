import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/koyas_button.dart';
import '../../store/providers/store_provider.dart';
import '../models/order.dart';
import '../widgets/order_card.dart';

class OrderHistoryScreen extends ConsumerStatefulWidget {
  const OrderHistoryScreen({super.key});

  @override
  ConsumerState<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends ConsumerState<OrderHistoryScreen> {
  bool _activeOnly = false;

  bool _isActive(CustomerOrder order) => !{
    OrderStatus.delivered,
    OrderStatus.collected,
    OrderStatus.cancelled,
    OrderStatus.rejected,
  }.contains(order.status);

  @override
  Widget build(BuildContext context) {
    final orders = ref.watch(storeProvider).orders;
    final visible = _activeOnly
        ? orders.where(_isActive).toList(growable: false)
        : orders;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Your orders'),
      ),
      body: orders.isEmpty
          ? EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No orders yet',
              message: 'Your pickup and delivery orders will appear here.',
              action: KoyasButton(
                label: 'Start shopping',
                expand: false,
                onPressed: () => context.go('/home'),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.xxxl,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'View your order details or quickly reorder your essentials.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.inkSecondary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(
                            value: false,
                            label: Text('All orders'),
                          ),
                          ButtonSegment(value: true, label: Text('Active')),
                        ],
                        selected: {_activeOnly},
                        onSelectionChanged: (value) =>
                            setState(() => _activeOnly = value.first),
                      ),
                      const SizedBox(height: AppSpacing.xxl),
                      if (visible.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: AppSpacing.page,
                          ),
                          child: EmptyState(
                            icon: Icons.task_alt_rounded,
                            title: 'No active orders',
                            message: 'You are all caught up.',
                          ),
                        )
                      else
                        ...visible.map(
                          (order) => Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.lg,
                            ),
                            child: OrderCard(
                              order: order,
                              onReorder: () {
                                ref
                                    .read(storeProvider.notifier)
                                    .reorder(order.id);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text(
                                      'Available items added to cart.',
                                    ),
                                    action: SnackBarAction(
                                      label: 'View cart',
                                      onPressed: () => context.push('/cart'),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
