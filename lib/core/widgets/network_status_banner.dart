import 'package:flutter/material.dart';

import '../services/network_status.dart';
import '../theme/app_colors.dart';

class NetworkStatusBanner extends StatelessWidget {
  const NetworkStatusBanner({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: NetworkStatus.instance,
    builder: (context, offline, _) => Column(
      children: [
        if (offline)
          Material(
            color: AppColors.of(context).warningSoft,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Semantics(
                  liveRegion: true,
                  child: Row(
                    children: [
                      Icon(
                        Icons.wifi_off_rounded,
                        size: 20,
                        color: AppColors.of(context).warning,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          noInternetMessage,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        Expanded(child: child),
      ],
    ),
  );
}
