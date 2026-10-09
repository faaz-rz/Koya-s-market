import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';

class SelectionCard extends StatelessWidget {
  const SelectionCard({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.trailing,
    super.key,
  });

  final bool selected;
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: AnimatedContainer(
        duration:
            MediaQuery.disableAnimationsOf(context) ||
                MediaQuery.accessibleNavigationOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 180),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: selected
              ? AppColors.of(context).brandSoft
              : AppColors.of(context).surface,
          borderRadius: BorderRadius.circular(AppRadii.xl),
          border: Border.all(
            color: selected
                ? AppColors.of(context).brand500
                : AppColors.of(context).outline,
            width: 1.5,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadii.xl),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final stackTrailing =
                      trailing != null &&
                      (constraints.maxWidth < 340 ||
                          MediaQuery.textScalerOf(context).scale(14) > 20);
                  final accessory =
                      trailing ??
                      Icon(
                        selected
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: selected
                            ? AppColors.of(context).brand600
                            : AppColors.of(context).inkTertiary,
                      );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppColors.of(context).brand500
                                  : AppColors.of(context).surfaceMuted,
                              borderRadius: BorderRadius.circular(AppRadii.lg),
                            ),
                            child: Icon(
                              icon,
                              color: selected
                                  ? AppColors.of(context).onBrand
                                  : AppColors.of(context).inkSecondary,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  subtitle,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: AppColors.of(
                                          context,
                                        ).inkSecondary,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          if (!stackTrailing) ...[
                            const SizedBox(width: AppSpacing.sm),
                            accessory,
                          ],
                        ],
                      ),
                      if (stackTrailing) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Align(
                          alignment: Alignment.centerRight,
                          child: accessory,
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
