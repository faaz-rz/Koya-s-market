import 'package:flutter/material.dart';

abstract final class AppShadows {
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
