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
import '../../store/providers/store_provider.dart';
import '../../store/data/supabase_store_repository.dart';
import '../data/payment_repository.dart';
import '../models/checkout_models.dart';
import '../widgets/checkout_progress.dart';
import '../widgets/selection_card.dart';
import '../services/razorpay_checkout.dart';

class PaymentScreen extends ConsumerStatefulWidget {
  const PaymentScreen({super.key});

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  bool _submitting = false;
  late final String _idempotencyKey;
  RazorpayCheckout? _razorpayCheckout;

  @override
  void initState() {
    super.initState();
    _idempotencyKey =
        'checkout-${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(this)}';
  }

  @override
  void dispose() {
    _razorpayCheckout?.dispose();
    super.dispose();
  }

  Future<void> _placeOrder() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      final currentStore = ref.read(storeProvider);
      if (currentStore.paymentMethod == PaymentMethod.online &&
          !AppEnvironment.enableRazorpayPayments) {
        throw const StoreValidationException(
          'Online payments are not available in this release.',
        );
      }
      late final String id;
      if (AppEnvironment.hasSupabaseConfig) {
        final repository = SupabaseStoreRepository();
        id = await repository.placeOrder(
          store: currentStore,
          idempotencyKey: _idempotencyKey,
        );
        if (currentStore.paymentMethod == PaymentMethod.online) {
          final providerOrder = await PaymentRepository().createProviderOrder(
            id,
          );
          await (_razorpayCheckout ??= RazorpayCheckout()).open(
            order: providerOrder,
            customerEmail: currentStore.profile?.email ?? '',
            customerPhone: currentStore.profile?.phone ?? '',
          );
        }
        ref.read(storeProvider.notifier).finishRemoteCheckout(id);
        final bundle = await repository.loadStore();
        ref.read(storeProvider.notifier).hydrateRemoteBundle(bundle);
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 550));
        id = ref.read(storeProvider.notifier).placeOrder();
      }
      if (mounted) context.go('/order/confirmation/$id');
    } on StoreValidationException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } on PaymentException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Checkout could not be completed. Your cart is safe—please try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(storeProvider);
    if (store.cartItems.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Payment')),
        body: EmptyState(
          icon: Icons.remove_shopping_cart_outlined,
          title: 'There is nothing to pay for',
          message: 'Your cart is empty. Browse the store to start a new order.',
          action: KoyasButton(
            label: 'Browse products',
            expand: false,
            onPressed: () => context.go('/home'),
          ),
        ),
      );
    }

    final pickup = store.fulfilmentType == FulfilmentType.pickup;
    final methods = <PaymentMethod>[
      if (pickup) PaymentMethod.payAtStore,
      if (!pickup && store.cashOnDeliveryEnabled) PaymentMethod.cashOnDelivery,
      if (AppEnvironment.enableRazorpayPayments) PaymentMethod.online,
    ];
    if (methods.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Review and pay')),
        body: EmptyState(
          icon: Icons.payment_outlined,
          title: 'Payment is currently unavailable',
          message:
              'Payment on delivery is unavailable right now. Please try again later.',
          action: KoyasButton(
            label: 'Back',
            expand: false,
            onPressed: () => context.pop(),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Review and pay')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 860;
            final methodSection = _PaymentMethods(
              methods: methods,
              selected: store.paymentMethod,
            );
            final summary = const _CheckoutSummary();
            return SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1040),
                  child: Column(
                    children: [
                      CheckoutProgress(
                        currentStep: pickup ? 1 : 2,
                        includeScheduleStep: !pickup,
                      ),
                      const SizedBox(height: AppSpacing.xxxl),
                      if (wide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 3, child: methodSection),
                            const SizedBox(width: AppSpacing.xxl),
                            Expanded(flex: 2, child: summary),
                          ],
                        )
                      else ...[
                        methodSection,
                        const SizedBox(height: AppSpacing.xxl),
                        summary,
                      ],
                      const SizedBox(height: AppSpacing.xxl),
                      KoyasButton(
                        label: store.paymentMethod == PaymentMethod.online
                            ? 'Pay ${formatPrice(store.totalPaise)} securely'
                            : 'Place order · ${formatPrice(store.totalPaise)}',
                        loading: _submitting,
                        icon: store.paymentMethod == PaymentMethod.online
                            ? Icons.lock_rounded
                            : Icons.check_rounded,
                        onPressed: _placeOrder,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        store.paymentMethod == PaymentMethod.online
                            ? AppEnvironment.hasSupabaseConfig
                                  ? 'Razorpay securely processes UPI, card, and net-banking payments.'
                                  : 'Online payment is simulated in demo mode; no charge is made.'
                            : pickup
                            ? 'Pay by cash or UPI at the store when you collect your order.'
                            : 'Pay by cash or UPI when your order is delivered.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.inkSecondary,
                        ),
                      ),
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

class _PaymentMethods extends ConsumerWidget {
  const _PaymentMethods({required this.methods, required this.selected});

  final List<PaymentMethod> methods;
  final PaymentMethod selected;

  String _title(PaymentMethod method) => switch (method) {
    PaymentMethod.cashOnDelivery => 'Cash or UPI on delivery',
    PaymentMethod.payAtStore => 'Cash or UPI at pickup',
    PaymentMethod.online => 'UPI, card, or net banking',
  };

  String _subtitle(PaymentMethod method) => switch (method) {
    PaymentMethod.cashOnDelivery =>
      'Pay the delivery partner when your order arrives',
    PaymentMethod.payAtStore => 'Pay at the store when your order is ready',
    PaymentMethod.online => 'Secure Razorpay checkout · UPI recommended',
  };

  IconData _icon(PaymentMethod method) => switch (method) {
    PaymentMethod.cashOnDelivery => Icons.payments_outlined,
    PaymentMethod.payAtStore => Icons.storefront_outlined,
    PaymentMethod.online => Icons.account_balance_wallet_outlined,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Payment method',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'No online payment is required while placing this order.',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppColors.inkSecondary),
        ),
        const SizedBox(height: AppSpacing.xxl),
        ...methods.map(
          (method) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: SelectionCard(
              selected: selected == method,
              title: _title(method),
              subtitle: _subtitle(method),
              icon: _icon(method),
              onTap: () =>
                  ref.read(storeProvider.notifier).setPaymentMethod(method),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const KoyasSurface(
          color: AppColors.infoSoft,
          borderColor: AppColors.infoSoft,
          child: Row(
            children: [
              Icon(Icons.verified_user_outlined, color: AppColors.info),
              SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  'Prices and stock are revalidated on the server before every order.',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CheckoutSummary extends ConsumerWidget {
  const _CheckoutSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(storeProvider);
    final pickup = store.fulfilmentType == FulfilmentType.pickup;
    return KoyasSurface(
      elevated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Order summary', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.lg),
          _SummaryLine(
            icon: pickup
                ? Icons.storefront_outlined
                : Icons.delivery_dining_outlined,
            title: pickup ? 'Store pickup' : 'Home delivery',
            subtitle: pickup
                ? 'We will notify you when your order is ready'
                : '${DateFormat('EEE, d MMM').format(store.selectedDate)} · ${store.selectedSlotLabel}',
          ),
          if (!pickup && store.selectedAddress != null) ...[
            const SizedBox(height: AppSpacing.md),
            _SummaryLine(
              icon: Icons.location_on_outlined,
              title: store.selectedAddress!.label,
              subtitle: store.selectedAddress!.formatted,
            ),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Divider(),
          ),
          _PriceLine(
            label: '${store.cartCount} items',
            value: formatPrice(store.subtotalPaise + store.savingsPaise),
          ),
          if (store.savingsPaise > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            _PriceLine(
              label: 'Product savings',
              value: '−${formatPrice(store.savingsPaise)}',
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          _PriceLine(
            label: 'Delivery',
            value: store.deliveryChargePaise == 0
                ? 'Free'
                : formatPrice(store.deliveryChargePaise),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Divider(),
          ),
          _PriceLine(
            label: 'Total',
            value: formatPrice(store.totalPaise),
            strong: true,
          ),
        ],
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppColors.brand600),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: AppSpacing.xs),
              Text(
                subtitle,
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

class _PriceLine extends StatelessWidget {
  const _PriceLine({
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
