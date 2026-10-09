import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/price_format.dart';
import '../../../core/widgets/koyas_button.dart';
import '../../../core/widgets/koyas_surface.dart';
import '../../store/providers/store_provider.dart';
import '../models/checkout_models.dart';
import '../widgets/checkout_progress.dart';
import '../widgets/selection_card.dart';

class FulfilmentScreen extends ConsumerWidget {
  const FulfilmentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(storeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('How would you like it?')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CheckoutProgress(
                    currentStep: 0,
                    includeScheduleStep:
                        store.fulfilmentType == FulfilmentType.delivery,
                  ),
                  const SizedBox(height: AppSpacing.xxxl),
                  Text(
                    'Choose fulfilment',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Pick up at your convenience or have your groceries delivered.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.of(context).inkSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  SelectionCard(
                    selected: store.fulfilmentType == FulfilmentType.pickup,
                    title: 'Store pickup',
                    subtitle: store.pickupEnabled
                        ? 'Free · Ready in as little as 30 minutes'
                        : 'Currently unavailable',
                    icon: Icons.storefront_rounded,
                    onTap: () => _select(context, ref, FulfilmentType.pickup),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SelectionCard(
                    selected: store.fulfilmentType == FulfilmentType.delivery,
                    title: 'Home delivery',
                    subtitle: !store.deliveryEnabled
                        ? 'Currently unavailable'
                        : store.baseDeliveryChargePaise == 0
                        ? 'Free delivery'
                        : store.subtotalPaise >=
                              store.freeDeliveryThresholdPaise
                        ? 'Free delivery unlocked'
                        : '${formatPrice(store.baseDeliveryChargePaise)} · Free above ${formatPrice(store.freeDeliveryThresholdPaise)}',
                    icon: Icons.delivery_dining_rounded,
                    onTap: () => _select(context, ref, FulfilmentType.delivery),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  KoyasSurface(
                    color: AppColors.of(context).surfaceMuted,
                    borderColor: AppColors.of(context).surfaceMuted,
                    child: Row(
                      children: [
                        Icon(Icons.location_on_outlined),
                        SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(
                            'Koya Stores\n9-1, 43/5, Prashanth Nagar, Langar Houz,\nHyderabad, Telangana 500008, India',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxxl),
                  KoyasButton(
                    label: 'Continue',
                    icon: Icons.arrow_forward_rounded,
                    onPressed: () => context.push(
                      store.fulfilmentType == FulfilmentType.pickup
                          ? '/checkout/payment'
                          : '/checkout/delivery',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _select(BuildContext context, WidgetRef ref, FulfilmentType type) {
    try {
      ref.read(storeProvider.notifier).setFulfilment(type);
    } on StoreValidationException catch (error) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}
