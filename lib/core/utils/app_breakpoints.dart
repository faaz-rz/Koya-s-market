import 'package:flutter/widgets.dart';

abstract final class AppBreakpoints {
  static const compact = 600.0;
  static const medium = 900.0;
  static const maxContentWidth = 1180.0;
}

extension ResponsiveContext on BuildContext {
  double get screenWidth => MediaQuery.sizeOf(this).width;
  bool get isCompact => screenWidth < AppBreakpoints.compact;
  bool get isExpanded => screenWidth >= AppBreakpoints.medium;
}
