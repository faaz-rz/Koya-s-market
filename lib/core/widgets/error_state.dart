import 'package:flutter/material.dart';

import 'empty_state.dart';
import 'koyas_button.dart';

class ErrorState extends StatelessWidget {
  const ErrorState({required this.message, required this.onRetry, super.key});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.cloud_off_rounded,
      title: 'Something went wrong',
      message: message,
      action: KoyasButton(
        label: 'Try again',
        icon: Icons.refresh_rounded,
        expand: false,
        onPressed: onRetry,
      ),
    );
  }
}
