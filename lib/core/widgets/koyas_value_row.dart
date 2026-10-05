import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Keep totals and order details readable instead of squeezing enlarged text.
class KoyasValueRow extends StatelessWidget {
  const KoyasValueRow({
    required this.label,
    required this.value,
    this.labelStyle,
    this.valueStyle,
    super.key,
  });

  final String label;
  final String value;
  final TextStyle? labelStyle;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final labelText = Text(label, style: labelStyle);
      if (constraints.maxWidth < 280 ||
          MediaQuery.textScalerOf(context).scale(14) > 20) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            labelText,
            const SizedBox(height: AppSpacing.xs),
            Text(value, style: valueStyle),
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: labelText),
          const SizedBox(width: AppSpacing.md),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.45),
            child: Text(value, textAlign: TextAlign.right, style: valueStyle),
          ),
        ],
      );
    },
  );
}
