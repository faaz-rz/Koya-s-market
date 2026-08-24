import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

class KoyasLogo extends StatelessWidget {
  const KoyasLogo({this.compact = false, super.key});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Koyas Supermarket',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: compact ? 38 : 44,
            height: compact ? 38 : 44,
            decoration: const BoxDecoration(
              color: AppColors.brand600,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.eco_rounded,
              color: AppColors.surface,
              size: compact ? 22 : 26,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            'Koyas',
            style:
                (compact
                        ? Theme.of(context).textTheme.titleLarge
                        : Theme.of(context).textTheme.headlineMedium)
                    ?.copyWith(color: AppColors.ink),
          ),
        ],
      ),
    );
  }
}
