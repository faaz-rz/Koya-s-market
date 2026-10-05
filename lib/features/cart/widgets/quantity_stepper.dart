import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';

class QuantityStepper extends StatelessWidget {
  const QuantityStepper({
    required this.quantity,
    required this.onIncrement,
    required this.onDecrement,
    this.compact = false,
    super.key,
  });

  final int quantity;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.brandSoft,
        borderRadius: BorderRadius.circular(AppRadii.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Decrease quantity',
            visualDensity: VisualDensity.standard,
            constraints: compact
                ? const BoxConstraints.tightFor(width: 44, height: 44)
                : null,
            padding: compact ? EdgeInsets.zero : null,
            onPressed: onDecrement,
            icon: const Icon(Icons.remove_rounded, size: 18),
          ),
          Text('$quantity', style: Theme.of(context).textTheme.labelLarge),
          IconButton(
            tooltip: 'Increase quantity',
            visualDensity: VisualDensity.standard,
            constraints: compact
                ? const BoxConstraints.tightFor(width: 44, height: 44)
                : null,
            padding: compact ? EdgeInsets.zero : null,
            onPressed: onIncrement,
            icon: const Icon(Icons.add_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}
