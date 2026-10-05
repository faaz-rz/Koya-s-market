import 'package:flutter/material.dart';

/// Animate the incoming branch without swapping/remounting its Navigator.
/// This preserves each tab's scroll position and avoids overlapping tap targets.
class CustomerTabTransition extends StatefulWidget {
  const CustomerTabTransition({
    required this.index,
    required this.child,
    super.key,
  });
  final int index;
  final Widget child;

  @override
  State<CustomerTabTransition> createState() => _CustomerTabTransitionState();
}

class _CustomerTabTransitionState extends State<CustomerTabTransition>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
    value: 1,
  );
  late final _opacity = Tween<double>(
    begin: 0.8,
    end: 1,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
  bool get _reduceMotion =>
      MediaQuery.disableAnimationsOf(context) ||
      MediaQuery.accessibleNavigationOf(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduceMotion) _controller.value = 1;
  }

  @override
  void didUpdateWidget(CustomerTabTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index != oldWidget.index) {
      if (_reduceMotion) {
        _controller.value = 1;
      } else {
        _controller.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _opacity,
    child: RepaintBoundary(child: widget.child),
  );
}
