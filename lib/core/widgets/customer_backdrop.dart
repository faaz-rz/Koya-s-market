import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The same market canvas across customer browsing and checkout.
class CustomerBackdrop extends StatelessWidget {
  const CustomerBackdrop({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: AppColors.of(context).marketCream, child: child);
}
