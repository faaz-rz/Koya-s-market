import 'package:flutter/material.dart';

/// Short, purposeful motion with native navigation and a reduced-motion path.
abstract final class AppMotion {
  static bool reduce(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context) ||
      MediaQuery.accessibleNavigationOf(context);

  static Duration duration(BuildContext context, Duration normal) =>
      reduce(context) ? Duration.zero : normal;

  static AnimationStyle? dialogStyle(BuildContext context) =>
      reduce(context) ? AnimationStyle.noAnimation : null;

  static AnimationStyle sheetStyle(BuildContext context) => reduce(context)
      ? AnimationStyle.noAnimation
      : const AnimationStyle(
          duration: Duration(milliseconds: 220),
          reverseDuration: Duration(milliseconds: 180),
        );

  static final pageTransitions = PageTransitionsTheme(
    builders: {
      for (final entry in const PageTransitionsTheme().builders.entries)
        entry.key: _AccessiblePageTransitions(entry.value),
    },
  );
}

class _AccessiblePageTransitions extends PageTransitionsBuilder {
  const _AccessiblePageTransitions(this.native);

  final PageTransitionsBuilder native;

  @override
  Duration get transitionDuration => native.transitionDuration;

  @override
  Duration get reverseTransitionDuration => native.reverseTransitionDuration;

  @override
  DelegatedTransitionBuilder? get delegatedTransition {
    final delegate = native.delegatedTransition;
    if (delegate == null) return null;
    return (context, primary, secondary, allowSnapshotting, child) =>
        AppMotion.reduce(context)
        ? child
        : delegate(context, primary, secondary, allowSnapshotting, child);
  }

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => AppMotion.reduce(context)
      ? child
      : native.buildTransitions(
          route,
          context,
          animation,
          secondaryAnimation,
          child,
        );
}
