import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/utils/price_format.dart';
import '../../store/providers/store_provider.dart';
import '../models/product.dart';
import '../product_variants.dart';
import 'product_visual.dart';

Future<void> showProductVariantSheet({
  required BuildContext context,
  required ProductFamily family,
}) {
  FocusScope.of(context).unfocus();
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    sheetAnimationStyle: AppMotion.sheetStyle(context),
    builder: (_) => _ProductVariantSheet(family: family),
  );
}

class _ProductVariantSheet extends ConsumerStatefulWidget {
  const _ProductVariantSheet({required this.family});
  final ProductFamily family;
  @override
  ConsumerState<_ProductVariantSheet> createState() =>
      _ProductVariantSheetState();
}

class _ProductVariantSheetState extends ConsumerState<_ProductVariantSheet> {
  late final Map<String, int> _baseline, _selection;
  late final String? _user;
  String? _error;
  bool _confirming = false;
  @override
  void initState() {
    super.initState();
    final store = ref.read(storeProvider);
    _user = store.profile?.id;
    _baseline = {
      for (final product in widget.family.variants)
        product.id: store.cartQuantities[product.id] ?? 0,
    };
    _selection = {..._baseline};
    ref.listenManual(storeProvider.select((s) => s.cartQuantities), (_, cart) {
      if (!mounted ||
          _confirming ||
          ref.read(storeProvider).profile?.id != _user) {
        return;
      }
      setState(() {
        for (final id in _baseline.keys) {
          final draftDelta = (_selection[id] ?? 0) - _baseline[id]!;
          final restored = cart[id] ?? 0;
          _baseline[id] = restored;
          _selection[id] = math.max(0, restored + draftDelta);
        }
      });
    });
  }

  void _change(Product product, int delta) {
    final quantity = math.max(0, (_selection[product.id] ?? 0) + delta);
    if (delta > 0 &&
        (!product.isAvailable || quantity > product.stockQuantity)) {
      return;
    }
    setState(() {
      _selection[product.id] = quantity;
      _error = null;
    });
  }

  void _confirm() {
    if (_confirming) return;
    _confirming = true;
    try {
      ref
          .read(storeProvider.notifier)
          .confirmCartSelection(
            expectedUserId: _user,
            baseline: _baseline,
            selection: _selection,
          );
      Navigator.of(context).pop();
    } on StoreValidationException catch (error) {
      _confirming = false;
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(storeProvider);
    final variants = widget.family.variants
        .map((p) => store.productById(p.id) ?? p.copyWith(stockQuantity: 0))
        .toList();
    final scale = math.max(
      1.0,
      MediaQuery.textScalerOf(context).scale(14) / 14,
    );
    final total = variants.fold(
      0,
      (sum, p) => sum + p.effectivePricePaise * (_selection[p.id] ?? 0),
    );
    final count = _selection.values.fold(0, (sum, value) => sum + value);
    final hasChanges = _selection.keys.any(
      (id) => _selection[id] != _baseline[id],
    );
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: LayoutBuilder(
          builder: (context, constraints) => SizedBox(
            height: math.min(constraints.maxHeight * 0.92, 560 * scale),
            child: Column(
              children: [
                IconButton.filled(
                  key: const Key('close-variant-sheet'),
                  tooltip: 'Cancel selection',
                  onPressed: () => Navigator.of(context).pop(),
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.of(context).ink,
                    foregroundColor: AppColors.of(context).surface,
                    minimumSize: const Size(48, 48),
                  ),
                  icon: const Icon(Icons.close_rounded),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Material(
                    color: AppColors.of(context).surface,
                    clipBehavior: Clip.antiAlias,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                    child: SafeArea(
                      top: false,
                      child: Column(
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              key: const Key('variant-sheet-scroll'),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(20),
                                    child: Row(
                                      children: [
                                        SizedBox.square(
                                          dimension: 64,
                                          child: ProductVisual(
                                            product: variants.first,
                                            radius: 16,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                widget.family.name,
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.titleLarge,
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'Choose a pack size',
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.bodyMedium,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                    ),
                                    child: Text(
                                      'Quantity',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  SizedBox(
                                    height: 285 * scale,
                                    child: ListView.separated(
                                      key: const Key('variant-cards'),
                                      scrollDirection: Axis.horizontal,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                      ),
                                      itemCount: variants.length,
                                      separatorBuilder: (_, _) =>
                                          const SizedBox(width: 12),
                                      itemBuilder: (context, index) {
                                        final product = variants[index];
                                        return SizedBox(
                                          width: math.min(
                                            240,
                                            180 + (scale - 1) * 60,
                                          ),
                                          child: _VariantCard(
                                            product: product,
                                            quantity:
                                                _selection[product.id] ?? 0,
                                            onChange: (delta) =>
                                                _change(product, delta),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 20,
                                    ),
                                    child: Text(
                                      'Tap Confirm to update your cart. Closing cancels these changes.',
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                              ),
                            ),
                          ),
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                              child: Semantics(
                                liveRegion: true,
                                child: Text(
                                  _error!,
                                  style: TextStyle(
                                    color: AppColors.of(context).error,
                                  ),
                                ),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                            child: SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                key: const Key('confirm-variant-selection'),
                                onPressed:
                                    !_confirming && (count > 0 || hasChanges)
                                    ? _confirm
                                    : null,
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.all(16),
                                  minimumSize: const Size(0, 56),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                ),
                                child: LayoutBuilder(
                                  builder: (context, c) {
                                    final stacked =
                                        c.maxWidth < 260 || scale > 1.5;
                                    final amount = Text(
                                      'Item total: ${formatPrice(total)}',
                                      key: const Key('variant-item-total'),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    );
                                    return stacked
                                        ? Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              amount,
                                              const SizedBox(height: 8),
                                              const Text('Confirm'),
                                            ],
                                          )
                                        : Row(
                                            children: [
                                              Expanded(child: amount),
                                              const SizedBox(width: 12),
                                              const Text('Confirm'),
                                            ],
                                          );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
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

class _VariantCard extends StatelessWidget {
  const _VariantCard({
    required this.product,
    required this.quantity,
    required this.onChange,
  });
  final Product product;
  final int quantity;
  final ValueChanged<int> onChange;
  @override
  Widget build(BuildContext context) {
    final size = ProductVariants.variantLabel(product) ?? product.unit;
    return Container(
      key: Key('variant-option-${product.id}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.of(context).outline),
        borderRadius: BorderRadius.circular(20),
        color: AppColors.of(context).surface,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: ProductVisual(product: product, radius: 12)),
          const SizedBox(height: 8),
          if (quantity == 0)
            OutlinedButton(
              key: Key('variant-add-${product.id}'),
              onPressed: product.isAvailable ? () => onChange(1) : null,
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
              child: Text(product.isAvailable ? 'ADD' : 'Out of stock'),
            )
          else
            Container(
              key: Key('variant-quantity-${product.id}'),
              decoration: BoxDecoration(
                color: AppColors.of(context).brand600,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  _CounterButton(
                    key: Key('variant-remove-${product.id}'),
                    tooltip: 'Remove one $size',
                    icon: Icons.remove_rounded,
                    onPressed: () => onChange(-1),
                  ),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '$quantity',
                        style: TextStyle(
                          color: AppColors.of(context).surface,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  _CounterButton(
                    key: Key('variant-increment-${product.id}'),
                    tooltip: 'Add one $size',
                    icon: Icons.add_rounded,
                    onPressed:
                        product.isAvailable && quantity < product.stockQuantity
                        ? () => onChange(1)
                        : null,
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          Text(size, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          if (product.discountPercent > 0)
            Text(
              '${product.discountPercent}% OFF',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: AppColors.of(context).offer,
              ),
            ),
          Wrap(
            spacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                formatPrice(product.effectivePricePaise),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (product.discountPricePaise != null)
                Text(
                  formatPrice(product.pricePaise),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.of(context).inkTertiary,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CounterButton extends StatelessWidget {
  const _CounterButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    super.key,
  });
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    color: AppColors.of(context).surface,
    disabledColor: AppColors.of(context).brand300,
    icon: Icon(icon, size: 20),
  );
}
