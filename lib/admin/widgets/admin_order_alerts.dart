import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../router/admin_router.dart';
import '../../features/admin/notifications/staff_order_alerts.dart';
import '../../features/store/providers/store_provider.dart';

/// One session-wide listener survives navigation between staff pages.
class AdminOrderAlerts extends ConsumerStatefulWidget {
  const AdminOrderAlerts({required this.child, super.key});
  final Widget child;
  @override
  ConsumerState<AdminOrderAlerts> createState() => _AdminOrderAlertsState();
}

class _AdminOrderAlertsState extends ConsumerState<AdminOrderAlerts> {
  @override
  void initState() {
    super.initState();
    ref.listenManual(storeProvider, (_, next) {
      ref.read(staffOrderAlertsProvider.notifier).observe(next);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final alerts = ref.read(staffOrderAlertsProvider.notifier);
      alerts.onOpenOrders = () {
        if (!mounted || !ref.read(storeProvider).isAdminAccount) return;
        alerts.acknowledge();
        ref
            .read(adminRouterProvider)
            .go('/orders?focus=${DateTime.now().microsecondsSinceEpoch}');
      };
      alerts.observe(ref.read(storeProvider));
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
