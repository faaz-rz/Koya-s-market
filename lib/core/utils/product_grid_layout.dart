import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Keeps product grids consistent across phones, tablets, foldables and web.
/// Phones deliberately show three products per row, while larger layouts add
/// columns gradually instead of stretching cards until they become oversized.
abstract final class ProductGridLayout {
  static const compactCardBreakpoint = 190.0;

  static int columnsForWidth(double width) {
    if (width < 600) return 3;
    if (width < 840) return 4;
    if (width < 1080) return 5;
    return 6;
  }

  static double spacingForWidth(double width) =>
      width < 600 ? AppSpacing.sm : AppSpacing.md;

  static double cardWidthFor(double width) {
    final columns = columnsForWidth(width);
    final spacing = spacingForWidth(width);
    return (width - (spacing * (columns - 1))) / columns;
  }

  static bool usesCompactCards(double width) =>
      cardWidthFor(width) < compactCardBreakpoint;

  static double mainAxisExtent(BuildContext context, double width) {
    final compact = usesCompactCards(width);
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.5);
    final scaleAllowance = (textScale - 1) * (compact ? 92 : 120);
    return (compact ? 272 : 340) + scaleAllowance;
  }

  static SliverGridDelegate delegate(BuildContext context, double width) {
    final spacing = spacingForWidth(width);
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columnsForWidth(width),
      mainAxisExtent: mainAxisExtent(context, width),
      mainAxisSpacing: spacing,
      crossAxisSpacing: spacing,
    );
  }
}
