import 'package:flutter/material.dart';
import 'app_colors.dart';

abstract final class AppShadows {
  static List<BoxShadow> of(BuildContext context, {bool elevated = false}) => [
    BoxShadow(
      color: AppColors.of(context).shadow,
      offset: Offset(0, elevated ? 8 : 4),
      blurRadius: elevated ? 28 : 18,
      spreadRadius: -6,
    ),
  ];

  static const low = [
    BoxShadow(
      color: Color(0x0922352B),
      offset: Offset(0, 4),
      blurRadius: 14,
      spreadRadius: -3,
    ),
  ];

  static const medium = [
    BoxShadow(
      color: Color(0x1422352B),
      offset: Offset(0, 6),
      blurRadius: 24,
      spreadRadius: -2,
    ),
    BoxShadow(color: Color(0x0822352B), offset: Offset(0, 2), blurRadius: 6),
  ];
}
