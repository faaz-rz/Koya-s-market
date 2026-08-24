import 'package:flutter/material.dart';

abstract final class AppShadows {
  static const low = [
    BoxShadow(color: Color(0x0F182018), offset: Offset(0, 2), blurRadius: 8),
  ];

  static const medium = [
    BoxShadow(
      color: Color(0x14182018),
      offset: Offset(0, 6),
      blurRadius: 18,
      spreadRadius: -2,
    ),
    BoxShadow(color: Color(0x0A182018), offset: Offset(0, 2), blurRadius: 6),
  ];
}
