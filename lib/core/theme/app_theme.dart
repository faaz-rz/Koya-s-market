import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_motion.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

abstract final class AppTheme {
  static final light = _build(AppPalette.light);
  static final dark = _build(AppPalette.dark);
  static final customer = _customer(light);
  static final customerDark = _customer(dark);

  static ThemeData _customer(ThemeData theme) => theme.copyWith(
    scaffoldBackgroundColor: Colors.transparent,
    appBarTheme: theme.appBarTheme.copyWith(
      backgroundColor: Colors.transparent,
      centerTitle: true,
    ),
  );

  static ThemeData _build(AppPalette p) {
    final text = AppTypography.textTheme.apply(
      bodyColor: p.ink,
      displayColor: p.ink,
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadii.lg),
    );
    final scheme = ColorScheme(
      brightness: p.isDark ? Brightness.dark : Brightness.light,
      primary: p.brand600,
      onPrimary: p.onBrand,
      primaryContainer: p.brandSoft,
      onPrimaryContainer: p.brand700,
      secondary: p.brand500,
      onSecondary: p.onBrand,
      secondaryContainer: p.surfaceMuted,
      onSecondaryContainer: p.ink,
      tertiary: p.offer,
      onTertiary: p.onBrand,
      tertiaryContainer: p.peach,
      onTertiaryContainer: p.ink,
      error: p.error,
      onError: p.onBrand,
      errorContainer: p.errorSoft,
      onErrorContainer: p.error,
      surface: p.surface,
      surfaceContainerLowest: p.surface,
      surfaceContainerLow: p.surface,
      surfaceContainer: p.surfaceMuted,
      surfaceContainerHigh: p.surfaceMuted,
      surfaceContainerHighest: p.brandSoft,
      onSurface: p.ink,
      onSurfaceVariant: p.inkSecondary,
      outline: p.outlineStrong,
      outlineVariant: p.outline,
      shadow: p.shadow,
      scrim: const Color(0x99102016),
      inverseSurface: p.ink,
      onInverseSurface: p.surface,
      inversePrimary: p.brand300,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: scheme.brightness,
      fontFamily: 'Manrope',
      extensions: [p],
      colorScheme: scheme,
      scaffoldBackgroundColor: p.canvas,
      textTheme: text,
      pageTransitionsTheme: AppMotion.pageTransitions,
      appBarTheme: AppBarTheme(
        backgroundColor: p.canvas,
        foregroundColor: p.ink,
        titleTextStyle: text.titleLarge,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: p.isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.xxl),
          side: BorderSide(color: p.outline),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: shape,
          textStyle: text.labelLarge,
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 52),
          foregroundColor: p.brand700,
          side: BorderSide(color: p.outlineStrong),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: shape,
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.brand700,
          textStyle: text.labelLarge,
          minimumSize: const Size(48, 48),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: const CircleBorder(),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        hintStyle: text.bodyMedium?.copyWith(color: p.inkTertiary),
        labelStyle: text.bodyMedium?.copyWith(color: p.inkSecondary),
        floatingLabelStyle: text.bodySmall?.copyWith(color: p.brand700),
        prefixIconColor: p.inkSecondary,
        suffixIconColor: p.brand600,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          borderSide: BorderSide(color: p.outline),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          borderSide: BorderSide(color: p.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          borderSide: BorderSide(color: p.brand600, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          borderSide: BorderSide(color: p.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          borderSide: BorderSide(color: p.error, width: 1.5),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surface,
        selectedColor: p.brandSoft,
        disabledColor: p.surfaceMuted,
        side: BorderSide(color: p.outline),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        labelStyle: text.labelMedium?.copyWith(color: p.ink),
        secondaryLabelStyle: text.labelMedium?.copyWith(
          color: p.brand700,
          fontWeight: FontWeight.w700,
        ),
        checkmarkColor: p.brand700,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        showCheckmark: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: p.brandSoft,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? p.brand700
                : p.inkSecondary,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => text.labelMedium?.copyWith(
            color: states.contains(WidgetState.selected)
                ? p.brand700
                : p.inkSecondary,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w800
                : FontWeight.w500,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: p.surface,
        indicatorColor: p.brandSoft,
        selectedIconTheme: IconThemeData(color: p.brand700),
        unselectedIconTheme: IconThemeData(color: p.inkSecondary),
        selectedLabelTextStyle: text.labelLarge?.copyWith(color: p.brand700),
        unselectedLabelTextStyle: text.labelLarge?.copyWith(
          color: p.inkSecondary,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: text.headlineMedium,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.isDark ? p.surfaceMuted : p.ink,
        contentTextStyle: text.bodyMedium?.copyWith(
          color: p.isDark ? p.ink : p.surface,
        ),
        actionTextColor: p.isDark ? p.brand600 : p.brand300,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
      ),
      dividerTheme: DividerThemeData(color: p.outline, thickness: 1, space: 1),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.brand600,
        linearTrackColor: p.brandSoft,
        circularTrackColor: p.brandSoft,
      ),
    );
  }
}
