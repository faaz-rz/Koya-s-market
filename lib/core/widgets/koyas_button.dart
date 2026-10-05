import 'package:flutter/material.dart';
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
    final child = Semantics(
      button: true,
      label: loading ? '$label, loading' : label,
      excludeSemantics: true,
      enabled: !loading && onPressed != null,
      onTap: loading ? null : onPressed,
      child: FilledButton(
        onPressed: loading ? null : onPressed,
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
      ),
    );

    return expand ? SizedBox(width: double.infinity, child: child) : child;
  }
}
