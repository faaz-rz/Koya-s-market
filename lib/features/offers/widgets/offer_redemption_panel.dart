import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/price_format.dart';
import '../../store/providers/store_provider.dart';
import '../models/store_offer.dart';

class OfferRedemptionPanel extends ConsumerWidget {
  const OfferRedemptionPanel({super.key});

  Future<void> _chooseOffer(
    BuildContext context,
    WidgetRef ref,
    StoreState store,
  ) async {
    final code = await showDialog<String>(
      context: context,
      animationStyle: AppMotion.dialogStyle(context),
      builder: (context) => _OfferPickerDialog(store: store),
    );
    if (code == null || !context.mounted) return;
    try {
      ref.read(storeProvider.notifier).applyOffer(code);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Offer ${code.toUpperCase()} applied.')),
      );
    } on StoreValidationException catch (error) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(storeProvider);
    final selected = store.selectedOffer;
    final applied = store.appliedOffer;
    final reason = selected == null
        ? null
        : store.offerIneligibilityReason(selected);
    final freeProduct = store.freeOfferProduct;

    return Container(
      key: const Key('customer-offer-panel'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: applied == null ? AppColors.surfaceMuted : AppColors.successSoft,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(
          color: applied == null ? AppColors.outline : AppColors.success,
        ),
      ),
      child: selected == null
          ? LayoutBuilder(
              builder: (context, constraints) {
                final prompt = Row(
                  children: [
                    const Icon(Icons.local_offer_outlined),
                    const SizedBox(width: AppSpacing.sm),
                    const Expanded(child: Text('Have an offer code?')),
                  ],
                );
                final button = TextButton(
                  key: const Key('customer-choose-offer'),
                  onPressed: () => _chooseOffer(context, ref, store),
                  child: const Text('View offers'),
                );
                if (constraints.maxWidth < 320 ||
                    MediaQuery.textScalerOf(context).scale(14) > 20) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      prompt,
                      const SizedBox(height: AppSpacing.xs),
                      button,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: prompt),
                    button,
                  ],
                );
              },
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      applied == null
                          ? Icons.info_outline_rounded
                          : Icons.check_circle_rounded,
                      color: applied == null
                          ? AppColors.warning
                          : AppColors.success,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${selected.code} · ${selected.title}',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          if (reason != null)
                            Text(
                              reason,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: AppColors.warning),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      key: const Key('customer-remove-offer'),
                      tooltip: 'Remove offer',
                      onPressed: ref.read(storeProvider.notifier).removeOffer,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                if (applied != null) ...[
                  if (store.offerDiscountPaise > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.sm),
                      child: Text(
                        'You save ${formatPrice(store.offerDiscountPaise)} with this offer.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.success,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  if (freeProduct != null)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Text(
                        'Free: ${applied.freeQuantity} × ${freeProduct.name}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.success,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ],
            ),
    );
  }
}

class _OfferPickerDialog extends StatefulWidget {
  const _OfferPickerDialog({required this.store});

  final StoreState store;

  @override
  State<_OfferPickerDialog> createState() => _OfferPickerDialogState();
}

class _OfferPickerDialogState extends State<_OfferPickerDialog> {
  final _code = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  String _benefit(StoreOffer offer) {
    final parts = <String>[];
    if (offer.discountType == OfferDiscountType.flat) {
      parts.add('${formatPrice(offer.discountValue)} off');
    } else if (offer.discountType == OfferDiscountType.percentage) {
      final cap = offer.maximumDiscountPaise == null
          ? ''
          : ' up to ${formatPrice(offer.maximumDiscountPaise!)}';
      parts.add('${offer.discountValue}% off$cap');
    }
    if (offer.hasFreeProduct) {
      final product = widget.store.productById(offer.freeProductId!);
      parts.add(
        '${offer.freeQuantity} × ${product?.name ?? 'free product'} free',
      );
    }
    return parts.join(' · ');
  }

  void _apply(String value) {
    final offer = widget.store.offerByCode(value);
    if (offer == null) {
      setState(() => _error = 'Offer code was not found.');
      return;
    }
    final reason = widget.store.offerIneligibilityReason(offer);
    if (reason != null) {
      setState(() => _error = reason);
      return;
    }
    Navigator.of(context).pop(offer.code);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final offers = widget.store.offers
        .where((offer) => offer.isLiveAt(now))
        .toList(growable: false);
    return AlertDialog(
      title: const Text('Offers for your basket'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const Key('customer-offer-code'),
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                onSubmitted: _apply,
                decoration: InputDecoration(
                  labelText: 'Offer code',
                  hintText: 'Example: CART10',
                  errorText: _error,
                  prefixIcon: const Icon(Icons.confirmation_number_outlined),
                  suffixIcon: IconButton(
                    key: const Key('customer-apply-offer-code'),
                    tooltip: 'Apply code',
                    onPressed: () => _apply(_code.text),
                    icon: const Icon(Icons.arrow_forward_rounded),
                  ),
                ),
              ),
              if (offers.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Available offers',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                for (final offer in offers)
                  _CustomerOfferTile(
                    offer: offer,
                    benefit: _benefit(offer),
                    reason: widget.store.offerIneligibilityReason(offer),
                    onApply: () => _apply(offer.code),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _CustomerOfferTile extends StatelessWidget {
  const _CustomerOfferTile({
    required this.offer,
    required this.benefit,
    required this.reason,
    required this.onApply,
  });

  final StoreOffer offer;
  final String benefit;
  final String? reason;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: Key('customer-offer-${offer.code}'),
      child: ListTile(
        title: Text('${offer.code} · ${offer.title}'),
        subtitle: Text(
          '$benefit\nMinimum basket: ${formatPrice(offer.minimumSubtotalPaise)}${reason == null ? '' : '\n$reason'}',
        ),
        isThreeLine: reason != null,
        trailing: TextButton(
          onPressed: reason == null ? onApply : null,
          child: const Text('Apply'),
        ),
      ),
    );
  }
}
