import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'four_dot_loader.dart';

class KoyasButton extends StatelessWidget {
  const KoyasButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = true,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    final colors = AppColors.of(context);
    final active = !loading && onPressed != null;
    final child = FilledButton(
      onPressed: loading ? null : onPressed,
      style: active
          ? FilledButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              foregroundColor: colors.onBrand,
            )
          : null,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Keep the label laid out during loading so compact buttons do not
          // shrink or move surrounding controls while a request is running.
          AnimatedOpacity(
            opacity: loading ? 0 : 1,
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 140),
            child: Row(
              key: const ValueKey('label'),
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20),
                  const SizedBox(width: 8),
                ],
                Flexible(child: Text(label, textAlign: TextAlign.center)),
              ],
            ),
          ),
          if (loading) const FourDotLoader(size: 24),
        ],
      ),
    );

    final button = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        gradient: active
            ? LinearGradient(colors: [colors.brand600, colors.brand500])
            : null,
        boxShadow: active
            ? [
                BoxShadow(
                  color: colors.brand600.withValues(alpha: 0.15),
                  offset: const Offset(0, 5),
                  blurRadius: 14,
                  spreadRadius: -4,
                ),
              ]
            : null,
      ),
      child: child,
    );
    final accessible = Semantics(
      button: true,
      label: loading ? '$label, loading' : label,
      excludeSemantics: true,
      enabled: !loading && onPressed != null,
      onTap: loading ? null : onPressed,
      child: button,
    );
    return expand
        ? SizedBox(width: double.infinity, child: accessible)
        : accessible;
  }
}
