import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Keeps product grids consistent across phones, tablets, foldables and web.
/// Uses compact columns where space permits, with fewer columns on narrow
/// screens or at large text sizes so names and cart controls remain usable.
abstract final class ProductGridLayout {
  static const compactCardBreakpoint = 190.0;

  static int columnsForWidth(double width, {double textScale = 1}) {
    final preferred = width < 600
        ? 3
        : width < 840
        ? 4
        : width < 1080
        ? 5
        : 6;
    final minimum = 108 + math.max(0, textScale - 1.35) * 40;
    final spacing = spacingForWidth(width);
    final fitting = ((width + spacing) / (minimum + spacing)).floor();
    return fitting.clamp(1, preferred);
  }

  static double spacingForWidth(double width) =>
      width < 600 ? AppSpacing.sm : AppSpacing.md;

  static double cardWidthFor(double width, {double textScale = 1}) {
    final columns = columnsForWidth(width, textScale: textScale);
    final spacing = spacingForWidth(width);
    return (width - (spacing * (columns - 1))) / columns;
  }

  static bool usesCompactCards(double width, {double textScale = 1}) =>
      cardWidthFor(width, textScale: textScale) < compactCardBreakpoint;

  static double mainAxisExtent(BuildContext context, double width) {
    final textScale = math.max(
      1.0,
      MediaQuery.textScalerOf(context).scale(14) / 14,
    );
    final compact = usesCompactCards(width, textScale: textScale);
    final scaleAllowance = (textScale - 1) * (compact ? 92 : 120);
    return (compact ? 240 : 324) + scaleAllowance;
  }

  static SliverGridDelegate delegate(BuildContext context, double width) {
    final spacing = spacingForWidth(width);
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columnsForWidth(width, textScale: scale),
      mainAxisExtent: mainAxisExtent(context, width),
      mainAxisSpacing: spacing,
      crossAxisSpacing: spacing,
    );
  }
}
