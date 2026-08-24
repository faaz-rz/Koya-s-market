import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/theme/app_colors.dart';
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

  Future<void> _addAddress() async {
    final address = await showDialog<CustomerAddress>(
      context: context,
      builder: (context) => const _AddAddressDialog(),
    );
    if (address != null) {
      try {
        final saved = AppEnvironment.hasSupabaseConfig
            ? await SupabaseStoreRepository().addAddress(address)
            : address;
        ref.read(storeProvider.notifier).addAddress(saved);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Address could not be saved. Please try again.'),
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Delivery address',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _addAddress,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Add new'),
                      ),
                    ],
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

class _AddAddressDialog extends StatefulWidget {
  const _AddAddressDialog();

  @override
  State<_AddAddressDialog> createState() => _AddAddressDialogState();
}

class _AddAddressDialogState extends State<_AddAddressDialog> {
  final _formKey = GlobalKey<FormState>();
  final _label = TextEditingController(text: 'Home');
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _line = TextEditingController();
  final _city = TextEditingController(text: 'Hyderabad');
  final _pincode = TextEditingController();

  @override
  void dispose() {
    _label.dispose();
    _name.dispose();
    _phone.dispose();
    _line.dispose();
    _city.dispose();
    _pincode.dispose();
    super.dispose();
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'This field is required' : null;

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      CustomerAddress(
        id: 'address-${DateTime.now().millisecondsSinceEpoch}',
        label: _label.text.trim(),
        recipientName: _name.text.trim(),
        phone: _phone.text.trim(),
        line1: _line.text.trim(),
        city: _city.text.trim(),
        pincode: _pincode.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add delivery address'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _label,
                  validator: _required,
                  decoration: const InputDecoration(labelText: 'Label'),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _name,
                  validator: _required,
                  decoration: const InputDecoration(
                    labelText: 'Recipient name',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _phone,
                  validator: (value) {
                    if (_required(value) != null) return _required(value);
                    return value!.replaceAll(RegExp(r'\D'), '').length < 10
                        ? 'Enter a valid phone number'
                        : null;
                  },
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone'),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _line,
                  validator: _required,
                  decoration: const InputDecoration(labelText: 'Address'),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _city,
                  validator: _required,
                  decoration: const InputDecoration(labelText: 'City'),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _pincode,
                  validator: (value) {
                    if (_required(value) != null) return _required(value);
                    return RegExp(r'^\d{6}$').hasMatch(value!.trim())
                        ? null
                        : 'Enter a valid 6-digit PIN';
                  },
                  maxLength: 6,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'PIN code'),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save address')),
      ],
    );
  }
}
