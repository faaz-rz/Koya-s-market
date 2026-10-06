import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/app_environment.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/four_dot_loader.dart';
import '../../../core/widgets/koyas_surface.dart';
import '../../store/providers/store_sync_health.dart';
import '../notifications/staff_order_alerts.dart';
import '../notifications/order_alert_platform.dart';

class StaffOrderAlertBar extends ConsumerWidget {
  const StaffOrderAlertBar({required this.onOpenOrders, super.key});
  final VoidCallback onOpenOrders;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(staffOrderAlertsProvider);
    final controller = ref.read(staffOrderAlertsProvider.notifier);
    final health = ref.watch(storeSyncHealthProvider);
    final live = health.live && health.failures == 0;
    final status = !AppEnvironment.hasSupabaseConfig
        ? 'Demo'
        : health.failures > 0
        ? 'Updates delayed'
        : live
        ? 'Live orders'
        : 'Reconnecting';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            Tooltip(
              message: health.lastSync == null
                  ? 'Waiting for a successful refresh'
                  : 'Last updated at ${TimeOfDay.fromDateTime(health.lastSync!).format(context)}. Live orders refresh immediately; backup refresh runs every five seconds if disconnected.',
              child: Chip(
                key: const Key('admin-live-order-status'),
                avatar: Icon(
                  live ? Icons.sensors_rounded : Icons.sync_rounded,
                  size: 18,
                  color: live ? AppColors.success : AppColors.warning,
                ),
                label: Text(status),
              ),
            ),
            if (!alerts.enabled || !alerts.sound)
              OutlinedButton.icon(
                key: const Key('admin-enable-order-alerts'),
                onPressed: alerts.enabling ? null : controller.enable,
                icon: alerts.enabling
                    ? const FourDotLoader(size: 18)
                    : const Icon(Icons.notifications_active_outlined, size: 18),
                label: Text(
                  alerts.enabled ? 'Enable sound' : 'Enable order alerts',
                ),
              ),
            if (alerts.sound) ...[
              TextButton.icon(
                key: const Key('admin-test-order-sound'),
                onPressed: controller.testSound,
                icon: const Icon(Icons.volume_up_outlined, size: 18),
                label: const Text('Test sound'),
              ),
              IconButton(
                key: const Key('admin-mute-order-sound'),
                tooltip: 'Mute order sound',
                onPressed: controller.mute,
                icon: const Icon(Icons.volume_off_outlined, size: 20),
              ),
            ],
            if (alerts.enabled &&
                alerts.notifications == BrowserAlertPermission.granted)
              const Text('Browser notifications on'),
          ],
        ),
        if (alerts.note != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              alerts.note!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (alerts.pending.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Semantics(
              liveRegion: true,
              child: KoyasSurface(
                key: const Key('admin-new-order-banner'),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    const Icon(
                      Icons.notifications_active_rounded,
                      color: AppColors.success,
                    ),
                    Text(
                      alerts.pending.length == 1
                          ? 'New order received'
                          : '${alerts.pending.length} new orders received',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    FilledButton(
                      key: const Key('admin-view-new-orders'),
                      onPressed: () {
                        controller.acknowledge();
                        onOpenOrders();
                      },
                      child: const Text('View orders'),
                    ),
                    TextButton(
                      onPressed: controller.acknowledge,
                      child: const Text('Dismiss'),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
