import '../widgets/address_editor_dialog.dart';
import '../widgets/delivery_pin_summary.dart';
import '../../../core/utils/transaction_request.dart';
import '../../../core/services/network_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/koyas_button.dart';
import '../../store/data/supabase_store_repository.dart';
import '../../store/providers/store_provider.dart';
import '../models/checkout_models.dart';
import '../widgets/checkout_progress.dart';
import '../widgets/selection_card.dart';

class DeliveryCheckoutScreen extends ConsumerStatefulWidget {
  const DeliveryCheckoutScreen({super.key});

  @override
  ConsumerState<DeliveryCheckoutScreen> createState() =>
      _DeliveryCheckoutScreenState();
}

class _DeliveryCheckoutScreenState
    extends ConsumerState<DeliveryCheckoutScreen> {
  late final TextEditingController _instructionsController;

  @override
  void initState() {
    super.initState();
    _instructionsController = TextEditingController(
      text: ref.read(storeProvider).deliveryInstructions,
    );
  }

  @override
  void dispose() {
    _instructionsController.dispose();
    super.dispose();
  }

  List<DateTime> _dates() {
    final now = DateTime.now();
    return List.generate(4, (index) {
      final date = now.add(Duration(days: index));
      return DateTime(date.year, date.month, date.day);
    });
  }

  Future<void> _addAddress([CustomerAddress? current]) async {
    final address = await showDialog<CustomerAddress>(
      context: context,
      animationStyle: AppMotion.dialogStyle(context),
      builder: (context) => AddressEditorDialog(address: current),
    );
    if (address != null && mounted) {
      final customerId = ref.read(storeProvider).profile?.id;
      try {
        final saved = AppEnvironment.hasSupabaseConfig
            ? await (current == null
                  ? SupabaseStoreRepository().addAddress(address)
                  : SupabaseStoreRepository().updateAddress(address))
            : address;
        if (!mounted || ref.read(storeProvider).profile?.id != customerId) {
          return;
        }
        if (current == null) {
          ref.read(storeProvider.notifier).addAddress(saved);
        } else {
          ref.read(storeProvider.notifier).updateAddress(saved);
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                connectionFailureMessage(
                  error,
                  transactionFailureMessage(
                    error,
                    'Address save was not confirmed. Check saved addresses before retrying.',
                  ),
                ),
              ),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(storeProvider);
    final selectedAddress = store.selectedAddress;
    final serviceable =
        selectedAddress != null &&
        store.serviceablePincodes.contains(selectedAddress.pincode);
    return Scaffold(
      appBar: AppBar(title: const Text('Delivery details')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CheckoutProgress(currentStep: 1),
                  const SizedBox(height: AppSpacing.xxxl),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final title = Text(
                        'Delivery address',
                        style: Theme.of(context).textTheme.headlineSmall,
                      );
                      final add = TextButton.icon(
                        onPressed: _addAddress,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Add new'),
                      );
                      if (MediaQuery.textScalerOf(context).scale(14) > 20) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            title,
                            const SizedBox(height: AppSpacing.xs),
                            add,
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: title),
                          add,
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ...store.addresses.map((address) {
                    final available = store.serviceablePincodes.contains(
                      address.pincode,
                    );
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: SelectionCard(
                        selected: address.id == store.selectedAddressId,
                        title: address.label,
                        subtitle:
                            '${address.recipientName} · ${address.formatted}',
                        icon: address.label.toLowerCase() == 'home'
                            ? Icons.home_rounded
                            : Icons.location_on_rounded,
                        trailing: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Icon(
                              address.id == store.selectedAddressId
                                  ? Icons.check_circle_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              color: address.id == store.selectedAddressId
                                  ? AppColors.brand600
                                  : AppColors.inkTertiary,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              available ? 'Serviceable' : 'Unavailable',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: available
                                        ? AppColors.success
                                        : AppColors.error,
                                  ),
                            ),
                          ],
                        ),
                        onTap: () => ref
                            .read(storeProvider.notifier)
                            .selectAddress(address.id),
                      ),
                    );
                  }),
                  if (selectedAddress?.deliveryPin != null)
                    DeliveryPinSummary(pin: selectedAddress!.deliveryPin!),
                  if (selectedAddress != null &&
                      selectedAddress.deliveryPin == null)
                    TextButton.icon(
                      onPressed: () => _addAddress(selectedAddress),
                      icon: const Icon(Icons.edit_location_alt_outlined),
                      label: const Text('Add a delivery pin'),
                    ),
                  if (selectedAddress != null && !serviceable)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.errorSoft,
                        borderRadius: BorderRadius.circular(AppRadii.md),
                      ),
                      child: Text(
                        'We do not deliver to PIN ${selectedAddress.pincode} yet. Choose another address.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.error,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.xxxl),
                  Text(
                    'Delivery day',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _dates().map((date) {
                        final selected = DateUtils.isSameDay(
                          date,
                          store.selectedDate,
                        );
                        return Padding(
                          padding: const EdgeInsets.only(right: AppSpacing.sm),
                          child: ChoiceChip(
                            selected: selected,
                            onSelected: (_) => ref
                                .read(storeProvider.notifier)
                                .setFulfilmentDate(date),
                            label: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                                vertical: AppSpacing.xs,
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    DateUtils.isSameDay(date, DateTime.now())
                                        ? 'Today'
                                        : DateFormat('EEE').format(date),
                                  ),
                                  Text(DateFormat('d MMM').format(date)),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  ...store.deliverySlots.map(
                    (slot) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: SelectionCard(
                        selected: store.selectedSlotLabel == slot.label,
                        title: slot.label,
                        subtitle: 'Doorstep delivery window',
                        icon: Icons.delivery_dining_rounded,
                        onTap: () => ref
                            .read(storeProvider.notifier)
                            .setSlot(slot.label),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextField(
                    controller: _instructionsController,
                    maxLength: 120,
                    maxLines: 3,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'Delivery instructions (optional)',
                      hintText:
                          'Landmark, gate code, or where to leave the order',
                      prefixIcon: Icon(Icons.notes_rounded),
                    ),
                    onChanged: ref
                        .read(storeProvider.notifier)
                        .setDeliveryInstructions,
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  KoyasButton(
                    label: 'Continue to payment',
                    icon: Icons.arrow_forward_rounded,
                    onPressed: serviceable
                        ? () => context.push('/checkout/payment')
                        : null,
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
