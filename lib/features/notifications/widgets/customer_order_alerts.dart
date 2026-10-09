import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/router/app_router.dart';
import '../../../core/widgets/four_dot_loader.dart';
import '../../orders/widgets/order_status_ui.dart';
import '../../store/providers/store_provider.dart';
import '../providers/customer_order_alerts.dart';
import '../providers/push_session.dart';

class CustomerOrderAlerts extends ConsumerStatefulWidget {
  const CustomerOrderAlerts({required this.child, super.key});
  final Widget child;
  @override
  ConsumerState<CustomerOrderAlerts> createState() =>
      _CustomerOrderAlertsState();
}

class _CustomerOrderAlertsState extends ConsumerState<CustomerOrderAlerts>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref
            .read(customerOrderAlertsProvider.notifier)
            .observe(ref.read(storeProvider));
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(customerOrderAlertsProvider.notifier).restore();
      ref.read(pushSessionProvider).refresh();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _open(String id) {
    if (!mounted || !ref.read(storeProvider).isAuthenticated) return;
    ref.read(customerOrderAlertsProvider.notifier).dismiss();
    ref.read(appRouterProvider).go('/order/$id');
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      storeProvider,
      (_, next) => ref.read(customerOrderAlertsProvider.notifier).observe(next),
    );
    ref.read(customerOrderAlertsProvider.notifier).onOpenOrder = _open;
    final alerts = ref.watch(customerOrderAlertsProvider);
    final order = alerts.updates.lastOrNull;
    return Stack(
      children: [
        widget.child,
        if (order != null)
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            left: 12,
            right: 12,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(20),
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Semantics(
                      liveRegion: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            alerts.updates.length == 1
                                ? order.customerStatusLabel
                                : '${alerts.updates.length} order updates',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Order #${order.customerDisplayNumber}: ${order.customerStatusMessage}',
                          ),
                          Wrap(
                            spacing: 8,
                            children: [
                              TextButton(
                                onPressed: () => _open(order.id),
                                child: const Text('View order'),
                              ),
                              TextButton(
                                onPressed: ref
                                    .read(customerOrderAlertsProvider.notifier)
                                    .dismiss,
                                child: const Text('Dismiss'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class CustomerAlertSettings extends ConsumerWidget {
  const CustomerAlertSettings({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(customerOrderAlertsProvider);
    final controller = ref.read(customerOrderAlertsProvider.notifier);
    final push = ref.watch(pushSessionStatusProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            push.ready
                ? 'Order alerts appear on your lock screen and stay in the notification tray until you open or dismiss them.'
                : push.available
                ? 'Allow notifications to get pickup and delivery updates, including when your phone is locked.'
                : 'Pickup and delivery updates appear while the app is open.',
          ),
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                key: const Key('enable-customer-alerts'),
                onPressed: alerts.enabling ? null : controller.enable,
                icon: alerts.enabling
                    ? const FourDotLoader(size: 20)
                    : const Icon(Icons.notifications_active_outlined),
                label: Text(
                  alerts.enabled
                      ? 'Check device alerts'
                      : 'Enable device alerts',
                ),
              ),
              if (alerts.enabled)
                TextButton.icon(
                  onPressed: () => controller.mute(alerts.sound),
                  icon: Icon(
                    alerts.sound
                        ? Icons.volume_up_outlined
                        : Icons.volume_off_outlined,
                  ),
                  label: Text(alerts.sound ? 'Mute sound' : 'Turn sound on'),
                ),
              if (push.available)
                TextButton.icon(
                  onPressed: controller.openSettings,
                  icon: const Icon(Icons.settings_outlined),
                  label: const Text('Phone notification settings'),
                ),
            ],
          ),
          if (alerts.note != null)
            Text(alerts.note!, style: Theme.of(context).textTheme.bodySmall),
          if (push.message != null)
            Text(push.message!, style: Theme.of(context).textTheme.bodySmall),
          if (push.available)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'If alerts are missing, check Koya Stores notifications and lock-screen visibility in your phone settings.',
              ),
            ),
        ],
      ),
    );
  }
}
