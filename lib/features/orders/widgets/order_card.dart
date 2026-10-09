import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/price_format.dart';
import '../../../core/widgets/koyas_surface.dart';
import '../../checkout/models/checkout_models.dart';
import '../../products/widgets/product_visual.dart';
import '../models/order.dart';
import 'order_status_ui.dart';

class OrderCard extends StatelessWidget {
  const OrderCard({required this.order, this.onReorder, super.key});

  final CustomerOrder order;
  final VoidCallback? onReorder;

  @override
  Widget build(BuildContext context) {
    final first = order.items.first;
    final itemNames = order.items.map((item) => item.name).join(', ');
    final statusColor = AppColors.of(
      context,
    ).resolve(order.customerStatusColor);
    return KoyasSurface(
      elevated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked =
                  constraints.maxWidth < 320 ||
                  MediaQuery.textScalerOf(context).scale(14) > 20;
              final visual = Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: AppColors.of(
                    context,
                  ).illustrationTint(ProductVisual.colorFor(first.visualKey)),
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                ),
                child: Icon(
                  ProductVisual.iconFor(first.visualKey),
                  color: AppColors.of(context).inkSecondary,
                ),
              );
              final details = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Order #${order.displayReference.replaceFirst('KOY', '')}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    DateFormat('d MMM yyyy · h:mm a').format(order.createdAt),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.of(context).inkSecondary,
                    ),
                  ),
                ],
              );
              final status = Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(AppRadii.full),
                ),
                child: Text(
                  order.customerStatusLabel,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      visual,
                      const SizedBox(width: AppSpacing.md),
                      Expanded(child: details),
                      if (!stacked) ...[
                        const SizedBox(width: AppSpacing.sm),
                        status,
                      ],
                    ],
                  ),
                  if (stacked) ...[
                    const SizedBox(height: AppSpacing.md),
                    status,
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            itemNames,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Icon(
                order.fulfilmentType == FulfilmentType.pickup
                    ? Icons.storefront_outlined
                    : Icons.delivery_dining_outlined,
                size: 18,
                color: AppColors.of(context).inkSecondary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  order.fulfilmentType == FulfilmentType.pickup
                      ? 'Store pickup'
                      : 'Home delivery · ${order.slotLabel}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.of(context).inkSecondary,
                  ),
                ),
              ),
              Text(
                formatPrice(order.totalPaise),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Divider(),
          ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => context.push('/order/${order.id}'),
                  child: const Text('View details'),
                ),
              ),
              if (onReorder != null) ...[
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: onReorder,
                    child: const Text('Reorder'),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
