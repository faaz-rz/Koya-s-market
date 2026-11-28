import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Keeps product grids consistent across phones, tablets, foldables and web.
/// Uses compact columns where space permits, with fewer columns on narrow
/// screens or at large text sizes so names and cart controls remain usable.
abstract final class ProductGridLayout {
  static const titleLines = 3;
  static const titleLineHeight = 1.25;
  static const priceLineHeight = 1.2;
  static const packLineHeight = 1.15;
  static const packFontSize = 12.0;
  static const addFontSize = 13.0;
  static const optionsFontSize = 10.0;
  static const minimumActionHeight = 48.0;

  static double titleFontSize(double cardWidth) => cardWidth < 180 ? 13 : 15;
  static double priceFontSize(double cardWidth) => cardWidth < 180 ? 19 : 21;
  static double photoHeight(double cardWidth) =>
      (cardWidth * 1.05).clamp(104.0, 204.0);

  static int columnsForWidth(double width, {double textScale = 1}) {
    final preferred = width < 600
        ? 3
        : width < 840
        ? 4
        : width < 1080
        ? 5
        : 6;
    // At large text sizes, preserve room for names and accessible cart controls
    // instead of squeezing two heavily truncated cards onto a narrow phone.
    final minimum = 108 + math.max(0, textScale - 1.05) * 100;
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

  static double actionHeight(TextScaler scaler) {
    final packHeight = scaler.scale(packFontSize) * packLineHeight * 2;
    final addHeight =
        (scaler.scale(addFontSize) + scaler.scale(optionsFontSize)) *
        packLineHeight;
    return math.max(
      minimumActionHeight,
      math.max(packHeight, addHeight).ceil() + AppSpacing.sm,
    );
  }

  static double mainAxisExtent(BuildContext context, double width) {
    final scaler = MediaQuery.textScalerOf(context);
    final cardWidth = cardWidthFor(width, textScale: scaler.scale(14) / 14);
    // Flutter can round each of the title's lines up to a whole pixel.
    final titleLine = scaler.scale(titleFontSize(cardWidth)) * titleLineHeight;
    final priceHeight =
        scaler.scale(priceFontSize(cardWidth)) * priceLineHeight;
    return photoHeight(cardWidth) +
        actionHeight(scaler) +
        priceHeight.ceil() +
        titleLine.ceil() * titleLines +
        AppSpacing.md +
        AppSpacing.xxs;
  }

  static SliverGridDelegate delegate(BuildContext context, double width) {
    final spacing = spacingForWidth(width);
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columnsForWidth(width, textScale: scale),
      mainAxisExtent: mainAxisExtent(context, width),
      mainAxisSpacing: AppSpacing.lg,
      crossAxisSpacing: spacing,
    );
  }
}
