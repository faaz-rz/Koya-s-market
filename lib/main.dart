import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/config/app_environment.dart';
import 'core/services/backend_bootstrap.dart';
import 'core/theme/appearance_provider.dart';
import 'core/widgets/configuration_error_app.dart';
import 'features/notifications/services/push_gateway.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kReleaseMode && !AppEnvironment.hasProductionCustomerConfig) {
    runApp(const ConfigurationErrorApp());
    return;
  }
  await BackendBootstrap.initialize();
  await FirebasePushGateway.initialize();
  final appearance = await DeviceAppearanceStorage().read();
  runApp(
    ProviderScope(
      overrides: [initialAppearanceProvider.overrideWithValue(appearance)],
      child: const KoyasApp(),
    ),
  );
}
