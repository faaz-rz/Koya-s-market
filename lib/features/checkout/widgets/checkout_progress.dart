import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';

class CheckoutProgress extends StatelessWidget {
  const CheckoutProgress({
    required this.currentStep,
    this.includeScheduleStep = true,
    super.key,
  });

  final int currentStep;
  final bool includeScheduleStep;

  @override
  Widget build(BuildContext context) {
    final labels = includeScheduleStep
        ? const ['Fulfilment', 'Schedule', 'Payment']
        : const ['Fulfilment', 'Payment'];
    return Semantics(
      label: 'Checkout step ${currentStep + 1} of ${labels.length}',
      child: Row(
        children: [
          for (var index = 0; index < labels.length; index++) ...[
            Expanded(
              child: Column(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    height: 4,
                    decoration: BoxDecoration(
                      color: index <= currentStep
                          ? AppColors.brand500
                          : AppColors.outline,
                      borderRadius: BorderRadius.circular(AppRadii.full),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    labels[index],
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: index <= currentStep
                          ? AppColors.brand700
                          : AppColors.inkTertiary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            if (index != labels.length - 1)
              const SizedBox(width: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}
