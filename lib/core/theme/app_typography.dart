import 'package:flutter/material.dart';

abstract final class AppTypography {
  static const _family = 'Manrope';

  static const textTheme = TextTheme(
    displayLarge: TextStyle(
      fontFamily: _family,
      fontSize: 32,
      height: 1.25,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.6,
    ),
    headlineLarge: TextStyle(
      fontFamily: _family,
      fontSize: 24,
      height: 1.33,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3,
    ),
    headlineMedium: TextStyle(
      fontFamily: _family,
      fontSize: 20,
      height: 1.4,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.2,
    ),
    titleLarge: TextStyle(
      fontFamily: _family,
      fontSize: 18,
      height: 1.33,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3,
    ),
    titleMedium: TextStyle(
      fontFamily: _family,
      fontSize: 16,
      height: 1.375,
      fontWeight: FontWeight.w600,
    ),
    bodyLarge: TextStyle(
      fontFamily: _family,
      fontSize: 16,
      height: 1.5,
      fontWeight: FontWeight.w400,
    ),
    bodyMedium: TextStyle(
      fontFamily: _family,
      fontSize: 14,
      height: 1.43,
      fontWeight: FontWeight.w400,
    ),
    labelLarge: TextStyle(
      fontFamily: _family,
      fontSize: 14,
      height: 1.43,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.1,
    ),
    labelMedium: TextStyle(
      fontFamily: _family,
      fontSize: 12,
      height: 1.33,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    ),
    bodySmall: TextStyle(
      fontFamily: _family,
      fontSize: 12,
      height: 1.33,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.1,
    ),
  );
}
