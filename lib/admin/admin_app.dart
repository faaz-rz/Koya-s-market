import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../core/widgets/network_status_banner.dart';
import 'router/admin_router.dart';
import 'widgets/admin_order_alerts.dart';

class KoyasAdminApp extends ConsumerWidget {
  const KoyasAdminApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(adminRouterProvider);
    return MaterialApp.router(
      title: 'Koya Stores Admin',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      builder: (context, child) => NetworkStatusBanner(
        child: AdminOrderAlerts(child: child ?? const SizedBox.shrink()),
      ),
      routerConfig: router,
    );
  }
}
