import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/price_format.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/koyas_button.dart';
import '../../../core/widgets/koyas_surface.dart';
import '../../checkout/models/checkout_models.dart';
import '../../store/providers/store_provider.dart';
import '../models/order.dart';

class OrderConfirmationScreen extends ConsumerWidget {
  const OrderConfirmationScreen({required this.orderId, super.key});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(storeProvider);
    CustomerOrder? order;
    for (final candidate in store.orders) {
      if (candidate.id == orderId) {
        order = candidate;
        break;
      }
    }
    if (order == null) {
      return Scaffold(
        body: EmptyState(
          icon: Icons.search_off_rounded,
          title: 'Order not found',
          message: 'We could not find that order.',
          action: KoyasButton(
            label: 'View orders',
            expand: false,
            onPressed: () => context.go('/orders'),
          ),
        ),
      );
    }
    final pickup = order.fulfilmentType == FulfilmentType.pickup;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                children: [
                  const SizedBox(height: AppSpacing.xxxl),
                  Container(
                    width: 104,
                    height: 104,
                    decoration: const BoxDecoration(
                      color: AppColors.successSoft,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 54,
                      color: AppColors.success,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  Text(
                    'Order confirmed!',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Thanks, ${store.profile?.name.split(' ').first ?? 'shopper'}. We have received your order.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.inkSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxxl),
                  KoyasSurface(
                    elevated: true,
                    child: Column(
                      children: [
                        _ConfirmationRow(
                          label: 'Order number',
                          value:
                              '#${order.displayReference.replaceFirst('KOY', '')}',
                        ),
                        const Divider(height: AppSpacing.xxl),
                        _ConfirmationRow(
                          label: pickup ? 'Pickup status' : 'Delivery',
                          value: pickup
                              ? 'We will notify you when it is ready'
                              : '${DateFormat('EEE, d MMM').format(order.fulfilmentDate)}\n${order.slotLabel}',
                        ),
                        const Divider(height: AppSpacing.xxl),
                        _ConfirmationRow(
                          label: 'Amount',
                          value: formatPrice(order.totalPaise),
                        ),
                        if (order.offerCode != null) ...[
                          const Divider(height: AppSpacing.xxl),
                          _ConfirmationRow(
                            label: 'Offer applied',
                            value: order.offerCode!,
                          ),
                        ],
                        const Divider(height: AppSpacing.xxl),
                        _ConfirmationRow(
                          label: 'Payment',
                          value: switch ((
                            order.paymentMethod,
                            order.paymentStatus,
                          )) {
                            (PaymentMethod.online, PaymentStatus.paid) =>
                              'Paid online',
                            (PaymentMethod.online, PaymentStatus.failed) =>
                              'Online payment failed',
                            (PaymentMethod.online, PaymentStatus.cancelled) =>
                              'Online payment cancelled',
                            (PaymentMethod.online, PaymentStatus.pending) =>
                              'Payment confirmation pending',
                            (PaymentMethod.payAtStore, _) =>
                              'Cash or UPI at pickup',
                            (PaymentMethod.cashOnDelivery, _) =>
                              'Cash or UPI on delivery',
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxxl),
                  KoyasButton(
                    label: 'View order',
                    icon: Icons.receipt_long_outlined,
                    onPressed: () => context.go('/order/$orderId'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextButton(
                    onPressed: () => context.go('/home'),
                    child: const Text('Continue shopping'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConfirmationRow extends StatelessWidget {
  const _ConfirmationRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.inkSecondary),
          ),
        ),
        Text(
          value,
          textAlign: TextAlign.right,
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ],
    );
  }
}
