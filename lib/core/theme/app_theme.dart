import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_motion.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

abstract final class AppTheme {
  // The gradient lives behind the whole customer navigator, including routes
  // during transitions. Staff pages retain a solid, readable workspace.
  static final customer = light.copyWith(
    scaffoldBackgroundColor: Colors.transparent,
    appBarTheme: light.appBarTheme.copyWith(
      backgroundColor: Colors.transparent,
      centerTitle: true,
      titleTextStyle: AppTypography.textTheme.titleLarge?.copyWith(
        color: AppColors.ink,
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
  );

  static final light = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    fontFamily: 'Manrope',
    scaffoldBackgroundColor: AppColors.canvas,
    colorScheme: const ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.brand600,
      onPrimary: AppColors.surface,
      primaryContainer: AppColors.brandSoft,
      onPrimaryContainer: AppColors.ink,
      secondary: AppColors.brand500,
      onSecondary: AppColors.surface,
      secondaryContainer: AppColors.surfaceMuted,
      onSecondaryContainer: AppColors.ink,
      tertiary: AppColors.offer,
      onTertiary: AppColors.surface,
      tertiaryContainer: Color(0xFFFFE9E2),
      onTertiaryContainer: AppColors.ink,
      error: AppColors.error,
      onError: AppColors.surface,
      errorContainer: AppColors.errorSoft,
      onErrorContainer: AppColors.error,
      surface: AppColors.surface,
      onSurface: AppColors.ink,
      onSurfaceVariant: AppColors.inkSecondary,
      outline: AppColors.outline,
      outlineVariant: AppColors.surfaceMuted,
      shadow: Color(0x24182018),
      scrim: Color(0x52182018),
      inverseSurface: AppColors.ink,
      onInverseSurface: AppColors.surface,
      inversePrimary: AppColors.brand300,
    ),
    textTheme: AppTypography.textTheme,
    pageTransitionsTheme: AppMotion.pageTransitions,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.canvas,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    cardTheme: const CardThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppRadii.xl)),
        side: BorderSide(color: AppColors.outline),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: const StadiumBorder(),
        textStyle: AppTypography.textTheme.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 52),
        foregroundColor: AppColors.brand700,
        side: const BorderSide(color: AppColors.brand500),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: const StadiumBorder(),
        textStyle: AppTypography.textTheme.labelLarge,
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      hintStyle: TextStyle(color: AppColors.inkSecondary),
      prefixIconColor: AppColors.inkSecondary,
      suffixIconColor: AppColors.inkSecondary,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppRadii.lg)),
        borderSide: BorderSide(color: AppColors.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppRadii.lg)),
        borderSide: BorderSide(color: AppColors.brand600, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppRadii.lg)),
        borderSide: BorderSide(color: AppColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppRadii.lg)),
        borderSide: BorderSide(color: AppColors.error, width: 2),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surface,
      selectedColor: AppColors.brandSoft,
      disabledColor: AppColors.surfaceMuted,
      side: const BorderSide(color: AppColors.outline),
      shape: const StadiumBorder(),
      labelStyle: AppTypography.textTheme.labelMedium?.copyWith(
        color: AppColors.ink,
      ),
      secondaryLabelStyle: AppTypography.textTheme.labelMedium?.copyWith(
        color: AppColors.brand700,
        fontWeight: FontWeight.w700,
      ),
      checkmarkColor: AppColors.brand700,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      showCheckmark: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppColors.brandSoft,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        return IconThemeData(
          color: states.contains(WidgetState.selected)
              ? AppColors.brand700
              : AppColors.inkSecondary,
        );
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        return AppTypography.textTheme.labelMedium?.copyWith(
          color: states.contains(WidgetState.selected)
              ? AppColors.brand700
              : AppColors.inkSecondary,
        );
      }),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.outline,
      thickness: 1,
      space: 1,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.brand600,
      linearTrackColor: AppColors.brandSoft,
      circularTrackColor: AppColors.brandSoft,
    ),
  );
}
